import os
import subprocess
import matplotlib.pyplot as plt
from fpdf import FPDF

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

def create_pie_chart(data, title, filename):
    labels = data.keys()
    sizes = data.values()
    plt.figure(figsize=(10, 6))
    plt.pie(sizes, labels=labels, autopct='%1.1f%%', startangle=140)
    plt.axis('equal')
    plt.title(title)
    plt.savefig(filename)
    plt.close()

def create_pdf_report(folder, report_data):
    pdf = FPDF()
    pdf.add_page()
    
    pdf.set_font("Arial", size=12)
    
    pdf.cell(200, 10, txt="Folder Report", ln=True, align='C')
    
    pdf.cell(200, 10, txt="Number of files by type:", ln=True)
    for file_type, count in report_data['file_counts'].items():
        pdf.cell(200, 10, txt=f"{file_type}: {count}", ln=True)
    
    pdf.cell(200, 10, txt="Total size by type:", ln=True)
    for file_type, size in report_data['total_sizes'].items():
        pdf.cell(200, 10, txt=f"{file_type}: {format_size(size)}", ln=True)
    
    pdf.cell(200, 10, txt="File owners by type:", ln=True)
    for file_type, owners in report_data['file_owners'].items():
        pdf.cell(200, 10, txt=f"{file_type}:", ln=True)
        for owner, count in owners.items():
            pdf.cell(200, 10, txt=f"  {owner}: {count}", ln=True)
    
    # Add pie charts to the PDF
    pdf.add_page()
    pdf.image("file_counts_pie_chart.png", x=10, y=20, w=180)
    
    pdf.add_page()
    pdf.image("total_sizes_pie_chart.png", x=10, y=20, w=180)
    
    pdf.output("folder_report.pdf")

def main(folder):
    file_types = {
        "Audio": [".mp3", ".wav", ".flac"],
        "Video": [".mp4", ".avi", ".mkv"],
        "Documents": [".pdf", ".docx", ".xlsx"],
        "Images": [".jpg", ".png", ".gif"]
    }

    report_data = {
        'file_counts': {},
        'total_sizes': {},
        'file_owners': {}
    }

    for file_type, extensions in file_types.items():
        report_data['file_counts'][file_type] = count_files_by_type(folder, extensions)
        report_data['total_sizes'][file_type] = total_size_by_type(folder, extensions)
        report_data['file_owners'][file_type] = file_owners_by_type(folder, extensions)

    # Create pie charts
    create_pie_chart(report_data['file_counts'], "Number of Files by Type", "file_counts_pie_chart.png")
    create_pie_chart(report_data['total_sizes'], "Total Size by Type", "total_sizes_pie_chart.png")

    # Create PDF report
    create_pdf_report(folder, report_data)

if __name__ == "__main__":
    import sys
    if len(sys.argv) != 2:
        print("Usage: python report.py /path/to/folder")
        sys.exit(1)
    main(sys.argv[1])
