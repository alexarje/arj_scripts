import os
import subprocess

def count_files_by_type(folder, extensions):
    count = 0
    for root, _, files in os.walk(folder):
        for file in files:
            if any(file.lower().endswith(ext) for ext in extensions):
                count += 1
    return count

def total_size_by_type(folder, extensions):
    total_size = 0
    for root, _, files in os.walk(folder):
        for file in files:
            if any(file.lower().endswith(ext) for ext in extensions):
                total_size += os.path.getsize(os.path.join(root, file))
    return total_size

def file_owners_by_type(folder, extensions):
    owners = {}
    for root, _, files in os.walk(folder):
        for file in files:
            if any(file.lower().endswith(ext) for ext in extensions):
                owner = subprocess.check_output(['ls', '-ld', os.path.join(root, file)]).split()[2].decode('utf-8')
                if owner in owners:
                    owners[owner] += 1
                else:
                    owners[owner] = 1
    return owners

def format_size(size):
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if size < 1024:
            return f"{size:.2f} {unit}"
        size /= 1024

def main(folder):
    file_types = {
        "Audio": [".mp3", ".wav", ".flac"],
        "Video": [".mp4", ".avi", ".mkv"],
        "Documents": [".pdf", ".docx", ".xlsx"],
        "Images": [".jpg", ".png", ".gif"]
    }

    print("Number of files by type:")
    for file_type, extensions in file_types.items():
        print(f"{file_type}: {count_files_by_type(folder, extensions)}")

    print("\nTotal size by type:")
    for file_type, extensions in file_types.items():
        print(f"{file_type}: {format_size(total_size_by_type(folder, extensions))}")

    print("\nFile owners by type:")
    for file_type, extensions in file_types.items():
        print(f"{file_type}:")
        owners = file_owners_by_type(folder, extensions)
        for owner, count in owners.items():
            print(f"  {owner}: {count}")

if __name__ == "__main__":
    import sys
    if len(sys.argv) != 2:
        print("Usage: python report.py /path/to/folder")
        sys.exit(1)
    main(sys.argv[1])
