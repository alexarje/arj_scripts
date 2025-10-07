import os
import PyPDF2

def count_words_in_pdf(file_path):
    try:
        with open(file_path, 'rb') as file:
            reader = PyPDF2.PdfReader(file)
            text = ''
            for page in reader.pages:
                text += page.extract_text()
            words = text.split()
            return len(words)
    except Exception as e:
        print(f"Error reading {file_path}: {e}")
        return 0

def rank_pdfs_by_word_count(directory):
    pdf_files = [f for f in os.listdir(directory) if f.endswith('.pdf')]
    word_counts = {}

    for pdf in pdf_files:
        file_path = os.path.join(directory, pdf)
        word_count = count_words_in_pdf(file_path)
        word_counts[pdf] = word_count

    ranked_pdfs = sorted(word_counts.items(), key=lambda item: item[1], reverse=True)

    for pdf, count in ranked_pdfs:
        print(f"{pdf}: {count} words")

if __name__ == "__main__":
    directory = input("Enter the directory containing the PDF files: ")
    rank_pdfs_by_word_count(directory)
