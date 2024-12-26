    from PIL import Image, ImageDraw
    
    # Open an image file
    image = Image.open('filename.jpg').convert('RGBA')
    
    # Create an alpha mask with the same size as the original image
    alpha_mask = Image.new('L', image.size, 0)
    draw = ImageDraw.Draw(alpha_mask)
    
    # Draw shapes on the mask using draw.ellipse, draw.rectangle, etc.
    draw.ellipse([2, 2, 700, 700], fill=255)
    
    # Apply the alpha mask to the original image
    image.putalpha(alpha_mask)
    
    # Save the resulting image
    image.save('output.png')

