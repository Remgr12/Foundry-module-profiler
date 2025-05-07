#!/bin/bash

# Script to find module.json files, save module names and manifest URLs,
# or load (download and unzip) module packages from a saved list.

# --- Configuration ---
# Default parent directory for saved module list files
DEFAULT_SCRIPT_OUTPUTS_DIR="saves"

# Extension for saved manifest list files
SAVE_FILE_EXTENSION=".txt"

MANIFEST_FILENAME="module.json"
# Directory to search for module.json files in 'save' mode
SEARCH_DIR="."

# Temporary file for downloaded manifests in 'load' mode
TEMP_MANIFEST_FILE="temp_downloaded_manifest.json"

# --- Helper Functions ---
show_usage() {
    echo "Foundry VTT Module Utility"
    echo "--------------------------"
    echo "Usage: $0 <mode> [options]"
    echo ""
    echo "Modes:"
    echo "  save"
    echo "            Prompts for an output filename. Scans local '$SEARCH_DIR' for module.json files."
    echo "            Saves module 'title' (or name/id) and 'manifest' URLs."
    echo "            Output is saved to '$DEFAULT_SCRIPT_OUTPUTS_DIR/<your_chosen_filename>${SAVE_FILE_EXTENSION}' (e.g., saves/my_setup.txt)."
    echo "            Format: Module Title/Name: [Name], Manifest URL: [URL]"
    echo ""
    echo "  load"
    echo "            Lists saved module profiles from '$DEFAULT_SCRIPT_OUTPUTS_DIR/*${SAVE_FILE_EXTENSION}'."
    echo "            Prompts you to choose a profile to load."
    echo "            For each module in the profile, it fetches its manifest from the 'Manifest URL',"
    echo "            then downloads and unzips the module package using the 'download' URL found in that manifest."
    echo "            Default install directory for modules: current directory ('.'), modules placed in './<module-id>/'."
    echo "            If [custom_module_install_directory] is provided, modules will be installed there (e.g., custom_dir/<module-id>/)."
    echo ""
    echo "Examples:"
    echo "  $0 save"
    echo "  $0 load                             # Loads modules to subdirectories in the current directory"
    echo "  $0 load ./my_foundry_modules        # Loads modules to subdirectories under './my_foundry_modules/'"
    echo ""
    echo "Prerequisites:"
    echo "  - jq: Required for parsing JSON."
    echo "  - wget: Required for 'load' mode (fetching manifests and modules)."
    echo "  - unzip: Required for 'load' mode."
    echo "  - mktemp: Required for 'load' mode (handling nested zips)."
    exit 1
}

# --- Prerequisite Check ---
command -v jq >/dev/null 2>&1 || { echo >&2 "Error: jq is not installed. Please install it. Aborting."; exit 1; }
command -v mktemp >/dev/null 2>&1 || { echo >&2 "Error: mktemp is not installed. It's required for load mode. Aborting."; exit 1; }
command -v unzip >/dev/null 2>&1 || { echo >&2 "Error: unzip is not installed. Please install it. Aborting."; exit 1; }


# --- Main Script Logic ---
MODE="$1"
# The second argument's meaning depends on the mode (only for 'load' mode's custom output dir)
ARGUMENT2="$2"

if [ -z "$MODE" ]; then
    echo "Error: No mode specified."
    show_usage
fi

# Create the main output directory for save files if it doesn't exist
if [ "$MODE" == "save" ] || { [ "$MODE" == "load" ] && [ ! -d "$DEFAULT_SCRIPT_OUTPUTS_DIR" ]; }; then
    if [ ! -d "$DEFAULT_SCRIPT_OUTPUTS_DIR" ]; then
        echo "Creating directory for save files: $DEFAULT_SCRIPT_OUTPUTS_DIR"
        mkdir -p "$DEFAULT_SCRIPT_OUTPUTS_DIR"
        if [ $? -ne 0 ]; then
            echo "Error: Could not create directory for save files '$DEFAULT_SCRIPT_OUTPUTS_DIR'. Aborting."
            exit 1
        fi
    fi
fi


# --- Mode: save ---
if [ "$MODE" == "save" ]; then
    echo "Mode: Save Module Names and Manifest URLs"
    
    read -r -p "Enter a name for your save file (e.g., my_module_setup): " output_basename
    if [ -z "$output_basename" ]; then
        echo "Error: Output filename cannot be empty. Aborting."
        exit 1
    fi
    
    FULL_OUTPUT_PATH="$DEFAULT_SCRIPT_OUTPUTS_DIR/${output_basename}${SAVE_FILE_EXTENSION}"
    
    OUTPUT_FILE_DIR=$(dirname "$FULL_OUTPUT_PATH")
    if [ ! -d "$OUTPUT_FILE_DIR" ]; then 
        mkdir -p "$OUTPUT_FILE_DIR"
        if [ $? -ne 0 ]; then
            echo "Error: Could not create directory for output file '$OUTPUT_FILE_DIR'. Aborting."
            exit 1
        fi
    fi

    > "$FULL_OUTPUT_PATH"
    
    echo "Searching for '$MANIFEST_FILENAME' files in '$SEARCH_DIR'..."
    echo "Output will be saved to: $FULL_OUTPUT_PATH"
    echo "----------------------------------------------------"

    find "$SEARCH_DIR" -type f -name "$MANIFEST_FILENAME" -print0 | while IFS= read -r -d $'\0' json_file; do
        echo "Processing file: $json_file"
        module_title=$(jq -r '.title // .name // .id // "Unknown Module"' "$json_file")
        manifest_url=$(jq -r '.manifest // empty' "$json_file")

        if [[ -n "$manifest_url" && "$manifest_url" != "null" ]]; then
            echo "  Found Module: \"$module_title\", Manifest URL: $manifest_url"
            echo "Module Title/Name: $module_title, Manifest URL: $manifest_url" >> "$FULL_OUTPUT_PATH"
        else
            echo "  Module: \"$module_title\", but no manifest URL found or it was null/empty in: $json_file"
        fi
    done
    echo "----------------------------------------------------"
    echo "Module name and manifest URL saving finished."

# --- Mode: load ---
elif [ "$MODE" == "load" ]; then
    command -v wget >/dev/null 2>&1 || { echo >&2 "Error: wget is not installed. It's required for load mode. Aborting."; exit 1; }
    command -v unzip >/dev/null 2>&1 || { echo >&2 "Error: unzip is not installed. It's required for load mode. Aborting."; exit 1; }

    echo "Mode: Load (Download & Unzip) Module Packages from Saved Profile"
    echo "----------------------------------------------------"

    echo "Available save files in '$DEFAULT_SCRIPT_OUTPUTS_DIR':"
    mapfile -t save_files < <(find "$DEFAULT_SCRIPT_OUTPUTS_DIR" -maxdepth 1 -type f -name "*${SAVE_FILE_EXTENSION}" -printf "%f\n" 2>/dev/null)

    if [ ${#save_files[@]} -eq 0 ]; then
        echo "No save files found in '$DEFAULT_SCRIPT_OUTPUTS_DIR' with extension '$SAVE_FILE_EXTENSION'."
        echo "Please create a save file first using the 'save' mode."
        exit 1
    fi

    for i in "${!save_files[@]}"; do
        printf "  %d) %s\n" "$((i+1))" "${save_files[$i]}"
    done
    echo ""

    selected_index=-1
    while [[ $selected_index -lt 0 || $selected_index -ge ${#save_files[@]} ]]; do
        read -r -p "Enter the number of the save file to load: " selection
        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -gt 0 ] && [ "$selection" -le ${#save_files[@]} ]; then
            selected_index=$((selection-1))
        else
            echo "Invalid selection. Please enter a number from the list."
        fi
    done

    SELECTED_SAVE_FILE_PATH="$DEFAULT_SCRIPT_OUTPUTS_DIR/${save_files[$selected_index]}"
    echo "Loading modules from: $SELECTED_SAVE_FILE_PATH"
    echo "----------------------------------------------------"

    if [ -n "$ARGUMENT2" ]; then 
        LOAD_BASE_DIR="$ARGUMENT2"
    else 
        LOAD_BASE_DIR="." # Default to current directory
    fi
    
    # Ensure the LOAD_BASE_DIR exists if it's custom and not "."
    if [[ "$LOAD_BASE_DIR" != "." && ! -d "$LOAD_BASE_DIR" ]]; then
        echo "Creating custom module install directory: $LOAD_BASE_DIR"
        mkdir -p "$LOAD_BASE_DIR"
        if [ $? -ne 0 ]; then
            echo "Error: Could not create custom module install directory '$LOAD_BASE_DIR'. Aborting."
            exit 1
        fi
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        profile_manifest_url=$(echo "$line" | sed -n 's/.*Manifest URL: \(.*\)/\1/p')
        if [ -z "$profile_manifest_url" ]; then
            echo "  Skipping line (could not parse Manifest URL): $line"
            continue
        fi
        
        module_display_name=$(echo "$line" | sed -n 's/Module Title\/Name: \(.*\), Manifest URL:.*/\1/p')
        echo "Processing entry for: \"$module_display_name\" (Manifest: $profile_manifest_url)"

        echo "  Fetching remote manifest from: $profile_manifest_url"
        wget --timeout=20 --tries=2 -q -O "$TEMP_MANIFEST_FILE" "$profile_manifest_url"
        if [ $? -ne 0 ]; then
            echo "  Error: Failed to download remote manifest for '$module_display_name' from '$profile_manifest_url'. Skipping."
            rm -f "$TEMP_MANIFEST_FILE"
            continue
        fi

        if [ ! -s "$TEMP_MANIFEST_FILE" ]; then
             echo "  Error: Downloaded remote manifest for '$module_display_name' is empty. Skipping."
             rm -f "$TEMP_MANIFEST_FILE"
             continue
        fi

        module_id=$(jq -r '.id // .name // empty' "$TEMP_MANIFEST_FILE")
        download_url=$(jq -r '.download // empty' "$TEMP_MANIFEST_FILE")

        if [ -z "$module_id" ]; then
            echo "  Error: Could not extract 'id' or 'name' from fetched manifest ($profile_manifest_url). Skipping."
            rm -f "$TEMP_MANIFEST_FILE"
            continue
        fi
        module_id_sanitized=$(echo "$module_id" | sed 's/[^a-zA-Z0-9_-]//g')
        if [ -z "$module_id_sanitized" ]; then
            echo "  Error: Module ID '$module_id' from fetched manifest resulted in an empty sanitized ID. Skipping."
            rm -f "$TEMP_MANIFEST_FILE"
            continue
        fi

        if [[ -z "$download_url" || "$download_url" == "null" ]]; then
            echo "  Error: No 'download' URL found in fetched manifest for module ID '$module_id_sanitized' (from $profile_manifest_url). Skipping."
            rm -f "$TEMP_MANIFEST_FILE"
            continue
        fi

        # MODULE_INSTALL_PATH is where the final module folder will reside
        MODULE_INSTALL_PATH="$LOAD_BASE_DIR/$module_id_sanitized"
        ZIP_FILE_PATH="$MODULE_INSTALL_PATH/module.zip" # Temporarily place zip here

        echo "  Module ID (from remote manifest): $module_id_sanitized"
        echo "  Download URL (from remote manifest): $download_url"
        echo "  Target install path: $MODULE_INSTALL_PATH"


        if [ -d "$MODULE_INSTALL_PATH" ] && [ -f "$MODULE_INSTALL_PATH/module.json" ]; then
            echo "  Skipping: Module directory '$MODULE_INSTALL_PATH' already exists and contains a module.json."
            rm -f "$TEMP_MANIFEST_FILE"
            continue
        fi
        
        # Ensure MODULE_INSTALL_PATH exists for downloading the zip into it, even if it might be temporary
        mkdir -p "$MODULE_INSTALL_PATH"
        if [ $? -ne 0 ]; then
            echo "  Error: Could not create directory '$MODULE_INSTALL_PATH' for download. Skipping."
            rm -f "$TEMP_MANIFEST_FILE"
            continue
        fi
        
        if [ -f "$ZIP_FILE_PATH" ] && [ ! -f "$MODULE_INSTALL_PATH/module.json" ]; then # Zip exists but not unzipped
             echo "  Info: '$ZIP_FILE_PATH' already exists. Will attempt to unzip."
        elif [ ! -f "$ZIP_FILE_PATH" ] ; then # Zip does not exist, download it
            echo "  Downloading module package to: $ZIP_FILE_PATH"
            wget --timeout=60 --tries=3 -q --show-progress -O "$ZIP_FILE_PATH" "$download_url"
            if [ $? -ne 0 ]; then
                echo "  Error: Failed to download module package from '$download_url'. wget exit code: $?. Removing incomplete file/dir."
                rm -f "$ZIP_FILE_PATH"
                # Attempt to remove the MODULE_INSTALL_PATH if it's empty, otherwise leave it.
                rmdir "$MODULE_INSTALL_PATH" 2>/dev/null 
                rm -f "$TEMP_MANIFEST_FILE"
                continue
            else
                echo "  Successfully downloaded: $ZIP_FILE_PATH"
            fi
        fi

        if [ -f "$ZIP_FILE_PATH" ]; then
            echo "  Unzipping '$ZIP_FILE_PATH' into '$MODULE_INSTALL_PATH/'"
            unzip -q -o "$ZIP_FILE_PATH" -d "$MODULE_INSTALL_PATH"
            unzip_status=$?
            if [ $unzip_status -eq 0 ]; then
                echo "  Successfully unzipped module '$module_id_sanitized'."
                echo "  Removing '$ZIP_FILE_PATH'."
                rm -f "$ZIP_FILE_PATH"

                # --- Handle nested directory structure ---
                if [ ! -f "$MODULE_INSTALL_PATH/module.json" ]; then
                    echo "  module.json not at root of '$MODULE_INSTALL_PATH'. Checking for a single nested module directory..."
                    
                    # Find top-level items in MODULE_INSTALL_PATH
                    # Using a subshell to avoid `shopt` affecting the main script
                    SINGLE_SUBDIR_PATH=""
                    ITEM_COUNT=0
                    FIRST_ITEM_NAME=""
                    IS_DIR=false

                    for item in "$MODULE_INSTALL_PATH"/* "$MODULE_INSTALL_PATH"/.*; do
                        if [[ -e "$item" ]]; then # Check if item exists (glob might return literal string if no match)
                            base_item=$(basename "$item")
                            if [[ "$base_item" != "." && "$base_item" != ".." ]]; then
                                ITEM_COUNT=$((ITEM_COUNT + 1))
                                FIRST_ITEM_NAME="$item"
                                if [[ -d "$item" ]]; then
                                    IS_DIR=true
                                fi
                            fi
                        fi
                    done
                    
                    if [ "$ITEM_COUNT" -eq 1 ] && [ "$IS_DIR" = true ]; then
                        SINGLE_SUBDIR_PATH="$FIRST_ITEM_NAME"
                        echo "  Found single item: $SINGLE_SUBDIR_PATH (is directory)"
                        if [ -f "$SINGLE_SUBDIR_PATH/module.json" ]; then
                            echo "  module.json found in nested directory: $SINGLE_SUBDIR_PATH"
                            TEMP_CONTENT_HOLDER=$(mktemp -d) # Create temp dir in system /tmp
                            if [ $? -eq 0 ] && [ -n "$TEMP_CONTENT_HOLDER" ]; then
                                echo "  Adjusting structure: Moving contents of '$SINGLE_SUBDIR_PATH' to '$MODULE_INSTALL_PATH' via temporary holder..."
                                # Move all contents from SINGLE_SUBDIR_PATH to TEMP_CONTENT_HOLDER
                                ( # Subshell for shopt and cd
                                    shopt -s dotglob
                                    mv "$SINGLE_SUBDIR_PATH"/* "$TEMP_CONTENT_HOLDER/" 2>/dev/null
                                    shopt -u dotglob
                                )
                                # Remove the original MODULE_INSTALL_PATH (which contained the single nested dir)
                                rm -rf "$MODULE_INSTALL_PATH" 
                                # Rename the TEMP_CONTENT_HOLDER to be the new MODULE_INSTALL_PATH
                                mv "$TEMP_CONTENT_HOLDER" "$MODULE_INSTALL_PATH"
                                if [ -f "$MODULE_INSTALL_PATH/module.json" ]; then
                                    echo "  Module structure successfully adjusted. module.json is now at root of '$MODULE_INSTALL_PATH'."
                                else
                                    echo "  Error: Failed to adjust module structure. module.json still not at root of '$MODULE_INSTALL_PATH' after move."
                                fi
                            else
                                echo "  Error: Could not create temporary directory for structure adjustment. Leaving as is."
                            fi
                            # rm -rf "$TEMP_CONTENT_HOLDER" # Clean up temp holder if it still exists (should have been moved)
                        else
                            echo "  Single subdirectory '$SINGLE_SUBDIR_PATH' does not contain module.json."
                        fi
                    elif [ "$ITEM_COUNT" -gt 1 ]; then
                        echo "  Multiple items found in '$MODULE_INSTALL_PATH' after unzip, and module.json not at root. Cannot automatically adjust structure."
                    else # ITEM_COUNT is 0 or 1 but not a directory, or other cases
                         echo "  No single nested directory found containing module.json."
                    fi
                fi # End nested structure check
            else # Unzip failed
                echo "  Error: Failed to unzip '$ZIP_FILE_PATH' (unzip exit code: $unzip_status). Please check the file and try manually."
            fi
        else # ZIP_FILE_PATH not found (should not happen if download was successful)
            if [ ! -f "$MODULE_INSTALL_PATH/module.json" ]; then
                 echo "  Error: Zip file '$ZIP_FILE_PATH' not found and module not already unzipped. Cannot proceed."
            fi
        fi
        rm -f "$TEMP_MANIFEST_FILE" 
        echo "  ----------------------------------"
    done < "$SELECTED_SAVE_FILE_PATH"
    
    rm -f "$TEMP_MANIFEST_FILE" 

    echo "----------------------------------------------------"
    echo "Module loading from profile finished."

else
    echo "Error: Invalid mode '$MODE'."
    show_usage
fi

echo "Script finished."

