#!/usr/bin/env python3
"""
Text to PDF Converter

A comprehensive script that converts all text files in a folder into a single, 
well-formatted PDF document. Each text file becomes a separate section with 
automatic table of contents generation.

Features:
    - Auto-generates PDF filename from folder name (e.g., 'notes-folder' → 'notes_folder.pdf')
    - Auto-generates PDF title from folder name (e.g., 'notes-folder' → 'Notes Folder')
    - Handles multiple text encodings (UTF-8, Latin-1, CP1252, ISO-8859-1)
    - Creates professional PDF layout with headers, spacing, and formatting
    - Generates table of contents with all file names
    - Preserves text formatting using monospace font
    - Robust error handling for problematic files
    - Cross-platform compatibility (Linux, macOS, Windows)

Use Cases:
    1. Research Documentation: Compile research notes, lab logs, and observations
    2. Project Archives: Create PDF archives of text-based project documentation
    3. Meeting Notes: Consolidate meeting minutes and notes into searchable PDFs
    4. Code Documentation: Combine multiple README files and documentation
    5. Academic Work: Compile course notes, assignments, and research materials
    6. Personal Journals: Create PDF books from diary entries or personal notes
    7. Data Analysis Logs: Combine experiment logs and analysis notes
    8. Software Development: Archive commit messages, changelogs, and dev notes

Examples:
    Basic usage (auto-generated filename and title):
        python3 text_to_pdf.py research_notes/
        # Creates: research_notes.pdf with title "Research Notes"
    
    Custom filename:
        python3 text_to_pdf.py lab_data/ -o experiment_results.pdf
        # Creates: experiment_results.pdf with title "Lab Data"
    
    Custom filename and title:
        python3 text_to_pdf.py meeting_notes/ -o "Q1_2025_Meetings.pdf" -t "Q1 2025 Team Meetings"
        # Creates: Q1_2025_Meetings.pdf with custom title
    
    Multiple folders:
        python3 text_to_pdf.py notes/admin/     # → admin.pdf
        python3 text_to_pdf.py notes/research/  # → research.pdf
        python3 text_to_pdf.py notes/personal/  # → personal.pdf

Dependencies:
    - reportlab (for PDF generation)
    - pathlib (built-in, for path handling)
    - argparse (built-in, for command-line interface)

Author: Generated for research note compilation
Version: 1.0
License: MIT
"""

import os
import sys
import argparse
from pathlib import Path
from reportlab.lib.pagesizes import letter, A4
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, PageBreak
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import inch
from reportlab.lib.enums import TA_LEFT, TA_CENTER
import glob

def read_text_file(filepath):
    """
    Read a text file with automatic encoding detection and error handling.
    
    Attempts to read the file with multiple common encodings. If all standard
    encodings fail, falls back to binary read with error replacement to ensure
    the file can always be processed.
    
    Args:
        filepath (Path): Path object pointing to the text file to read
        
    Returns:
        str: Content of the file as a string
        
    Encodings tried (in order):
        1. UTF-8 (most common modern encoding)
        2. Latin-1 (Western European languages)
        3. CP1252 (Windows Western European)
        4. ISO-8859-1 (Standard Western European)
        5. Binary with error replacement (fallback)
        
    Example:
        content = read_text_file(Path("notes.txt"))
    """
    encodings = ['utf-8', 'latin-1', 'cp1252', 'iso-8859-1']
    
    for encoding in encodings:
        try:
            with open(filepath, 'r', encoding=encoding) as file:
                return file.read()
        except UnicodeDecodeError:
            continue
    
    # If all encodings fail, read as binary and decode with errors='replace'
    with open(filepath, 'rb') as file:
        return file.read().decode('utf-8', errors='replace')

def create_pdf_from_text_files(folder_path, output_path, title="Text Files Collection"):
    """
    Create a professionally formatted PDF from all text files in a given folder.
    
    This function processes all .txt files in the specified folder and creates
    a single PDF document with the following structure:
    1. Title page with the specified title
    2. Table of contents listing all files
    3. Individual sections for each text file with headers
    4. Proper spacing and page breaks between sections
    
    Args:
        folder_path (str or Path): Path to the folder containing text files
        output_path (str): Path where the PDF file will be saved
        title (str, optional): Title for the PDF document. Defaults to "Text Files Collection"
        
    Returns:
        bool: True if PDF was created successfully, False otherwise
        
    Features:
        - Automatic file sorting (alphabetical order)
        - Professional typography with custom styles
        - Error handling for individual problematic files
        - Progress reporting during processing
        - HTML character escaping for content safety
        - Monospace font preservation for code and formatted text
        - A4 page size with 1-inch margins
        
    Raises:
        No exceptions are raised directly; errors are handled gracefully
        and reported to the user via console output.
        
    Example:
        success = create_pdf_from_text_files(
            folder_path="research_notes/",
            output_path="research_compilation.pdf",
            title="Research Notes Compilation"
        )
        if success:
            print("PDF created successfully!")
    """
    
    # Get all text files in the folder
    folder = Path(folder_path)
    text_files = list(folder.glob("*.txt"))
    
    if not text_files:
        print(f"No .txt files found in {folder_path}")
        return False
    
    # Sort files by name
    text_files.sort()
    
    print(f"Found {len(text_files)} text files")
    
    # Create PDF document
    doc = SimpleDocTemplate(
        output_path,
        pagesize=A4,
        rightMargin=inch,
        leftMargin=inch,
        topMargin=inch,
        bottomMargin=inch
    )
    
    # Define styles
    styles = getSampleStyleSheet()
    
    # Title style
    title_style = ParagraphStyle(
        'CustomTitle',
        parent=styles['Heading1'],
        fontSize=18,
        spaceAfter=30,
        alignment=TA_CENTER,
        textColor='black'
    )
    
    # File header style
    file_header_style = ParagraphStyle(
        'FileHeader',
        parent=styles['Heading2'],
        fontSize=14,
        spaceAfter=12,
        spaceBefore=20,
        textColor='black'
    )
    
    # Content style
    content_style = ParagraphStyle(
        'Content',
        parent=styles['Normal'],
        fontSize=10,
        spaceAfter=6,
        alignment=TA_LEFT,
        fontName='Courier'  # Monospace font to preserve formatting
    )
    
    # Build the document content
    story = []
    
    # Add main title
    story.append(Paragraph(title, title_style))
    story.append(Spacer(1, 20))
    
    # Add table of contents
    story.append(Paragraph("Table of Contents", file_header_style))
    for i, txt_file in enumerate(text_files, 1):
        story.append(Paragraph(f"{i}. {txt_file.name}", content_style))
    story.append(PageBreak())
    
    # Process each text file
    for i, txt_file in enumerate(text_files, 1):
        print(f"Processing {txt_file.name}...")
        
        # Add file header
        story.append(Paragraph(f"{i}. {txt_file.name}", file_header_style))
        story.append(Spacer(1, 12))
        
        try:
            # Read file content
            content = read_text_file(txt_file)
            
            # Split content into paragraphs and add to story
            paragraphs = content.split('\n')
            
            for paragraph in paragraphs:
                if paragraph.strip():  # Only add non-empty paragraphs
                    # Escape HTML characters and preserve line breaks
                    escaped_text = (paragraph.replace('&', '&amp;')
                                  .replace('<', '&lt;')
                                  .replace('>', '&gt;'))
                    story.append(Paragraph(escaped_text, content_style))
                else:
                    story.append(Spacer(1, 6))  # Add space for empty lines
            
        except Exception as e:
            error_msg = f"Error reading file {txt_file.name}: {str(e)}"
            print(error_msg)
            story.append(Paragraph(error_msg, content_style))
        
        # Add page break between files (except for the last one)
        if i < len(text_files):
            story.append(PageBreak())
    
    # Build the PDF
    try:
        doc.build(story)
        print(f"PDF created successfully: {output_path}")
        return True
    except Exception as e:
        print(f"Error creating PDF: {str(e)}")
        return False

def main():
    """
    Main entry point for the Text to PDF Converter command-line interface.
    
    Parses command-line arguments, validates input, and orchestrates the PDF
    creation process. Provides intelligent defaults for both filename and title
    generation based on the source folder name.
    
    Command-line Arguments:
        folder (str): Path to folder containing .txt files (required)
        -o, --output (str): Custom output PDF filename (optional)
        -t, --title (str): Custom PDF title (optional)
        
    Auto-generation Logic:
        - If no output filename specified: uses folder name with .pdf extension
          Example: "research-notes" → "research_notes.pdf"
        - If no title specified: uses folder name in title case with spaces
          Example: "research-notes" → "Research Notes"
          
    Exit Codes:
        0: Success - PDF created successfully
        1: Error - Invalid folder path, no files found, or PDF creation failed
        
    Validation Checks:
        - Verifies folder exists and is a directory
        - Ensures output path has .pdf extension
        - Handles path resolution and absolute path conversion
        
    Examples:
        # Minimal usage - auto-generates filename and title
        python3 text_to_pdf.py notes/meeting-minutes/
        # Result: meeting_minutes.pdf with title "Meeting Minutes"
        
        # Custom filename, auto-generated title
        python3 text_to_pdf.py data/experiment-logs/ -o lab_results.pdf
        # Result: lab_results.pdf with title "Experiment Logs"
        
        # Fully customized
        python3 text_to_pdf.py docs/ -o "Final_Report.pdf" -t "Project Documentation"
        # Result: Final_Report.pdf with title "Project Documentation"
    """
    parser = argparse.ArgumentParser(description="Convert text files in a folder to PDF")
    parser.add_argument("folder", help="Path to folder containing text files")
    parser.add_argument("-o", "--output", help="Output PDF filename (default: folder_name.pdf)")
    parser.add_argument("-t", "--title", help="Title for the PDF document (default: folder name)")
    
    args = parser.parse_args()
    
    folder_path = Path(args.folder)
    
    if not folder_path.exists():
        print(f"Error: Folder '{folder_path}' does not exist")
        sys.exit(1)
    
    if not folder_path.is_dir():
        print(f"Error: '{folder_path}' is not a directory")
        sys.exit(1)
    
    # Set default title to folder name if not provided
    if args.title:
        title = args.title
    else:
        # Convert folder name to readable title: "research-notes" → "Research Notes"
        title = folder_path.name.replace('-', ' ').replace('_', ' ').title()
    
    # Set default output filename if not provided
    if args.output:
        output_path = Path(args.output)
    else:
        # Convert folder name to safe filename: "research-notes" → "research_notes.pdf"
        clean_folder_name = folder_path.name.replace('-', '_').replace(' ', '_')
        output_path = Path.cwd() / f"{clean_folder_name}.pdf"
    
    # Ensure output has .pdf extension
    if not str(output_path).lower().endswith('.pdf'):
        output_path = Path(str(output_path) + '.pdf')
    
    # Convert to string for reportlab
    output_path = str(output_path)
    
    success = create_pdf_from_text_files(
        folder_path=folder_path,
        output_path=output_path,
        title=title
    )
    
    if success:
        print(f"\nSuccess! PDF saved as: {output_path}")
    else:
        print("\nFailed to create PDF")
        sys.exit(1)

if __name__ == "__main__":
    main()
