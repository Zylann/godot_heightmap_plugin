
class MDElement:
	def __init__(self, title, depth):
		self.title = title
		self.depth = depth
		self.line_index = None


TAG_TOC_START = "<!-- TOC -->"
TAG_TOC_END = "<!-- /TOC -->"


def remove_old_toc(lines):
	line_index = 0
	filtered_lines = []
	
	while line_index < len(lines):
		if TAG_TOC_START in lines[line_index]:
			while line_index < len(lines):
				line_index += 1

				if TAG_TOC_END in lines[line_index]:
					print("Removed old TOC")
					break
		else:
			filtered_lines.append(lines[line_index])

		line_index += 1

	return filtered_lines


def parse_headings(lines):
	elements = []
	prev_line = ""
	line_index = 0

	while line_index < len(lines):
		line = lines[line_index]
		elem = None

		if "===" in line:
			elem = MDElement(prev_line.strip(), 0)
			main_heading_line_index = line_index

		elif "---" in line:
			elem = MDElement(prev_line.strip(), 1)

		elif "###" in line:
			elem = MDElement(line[4:].strip(), 2)

		if elem is not None:
			elem.line_index = line_index
			elements.append(elem)

		prev_line = line
		line_index += 1

	return elements


def generate_toc_lines(elements):
	toc_lines = ["", TAG_TOC_START]
	
	for element in elements:
		line = ""
		for i in range(0, element.depth):
			line += "    "
		anchor = "#" + element.title.replace(" ", "-").replace(",", "").lower()
		line += "- [{0}]({1})".format(element.title, anchor)
		toc_lines.append(line)

	toc_lines.append(TAG_TOC_END)
	return toc_lines


def generate_toc(file_path, dst_path):
	print("Reading file", file_path)
	f = open(file_path)
	lines = f.read().splitlines()
	f.close()

	lines = remove_old_toc(lines)
	elements = parse_headings(lines)

	if len(elements) == 0:
		print("No elements found")
		return

	toc_lines = generate_toc_lines(elements)
	toc_line_index = elements[0].line_index + 1
	lines = lines[0:toc_line_index] + toc_lines + lines[toc_line_index+1:]

	final_text = "\n".join(lines)

	print("Writing", dst_path)
	f = open(dst_path, 'w+', newline='\n')
	f.write(final_text)
	f.close()

	print("Done")


if __name__ == "__main__":
	generate_toc("main.md", "main.md")
