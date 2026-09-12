import os
import re

def organize_background_images(directory="."):
    # Define supported image extensions
    image_extensions = ('.png', '.jpg', '.jpeg', '.webp', '.bmp', '.gif')

    # Regex pattern to match 'background<number>.<ext>' (case-insensitive)
    pattern = re.compile(r'^background(\d+)\.(png|jpg|jpeg|webp|bmp|gif)$', re.IGNORECASE)

    files = os.listdir(directory)
    used_numbers = set()
    other_images = []

    # Step 1: Identify existing background files and collect used numbers
    for filename in files:
        match = pattern.match(filename)
        if match:
            used_numbers.add(int(match.group(1)))
        elif filename.lower().endswith(image_extensions):
            other_images.append(filename)

    # Step 2: Assign missing numbers to the remaining image files
    current_no = 1
    for image in other_images:
        # Find the next number that is NOT currently present
        while current_no in used_numbers:
            current_no += 1

        # Extract extension and create new filename
        ext = os.path.splitext(image)[1]
        new_name = f"background{current_no}{ext}"

        # Perform the rename
        old_path = os.path.join(directory, image)
        new_path = os.path.join(directory, new_name)

        os.rename(old_path, new_path)
        print(f"Renamed: '{image}' -> '{new_name}'")

        # Mark this number as used and increment
        used_numbers.add(current_no)
        current_no += 1

    print("\nAll remaining images have been successfully renamed!")

if __name__ == "__main__":
    organize_background_images()
