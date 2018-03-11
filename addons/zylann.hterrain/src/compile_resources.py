filename = "default_shader.txt"
generated_warning = "\n// This is a generated file. Do not edit.\n\n"

lines = []
with open(filename) as f:
	for line in f:
		lines.append(line)

var_name = filename[:filename.find('.')] + "_code"
var_type = "const char *";
var_prefix = "s_"

with open("resources.gen.cpp", 'w') as f:
	f.write(generated_warning)
	f.write("#include \"resources.gen.h\"\n\n")
	f.write(var_type + var_prefix + var_name + " =")
	for line in lines:
		# TODO Any better way of escaping those special characters?
		oline = "\n\t\"" + line.replace('\t', "\\t").replace('\n', "\\n") + "\""
		f.write(oline)
	f.write(";\n")

with open("resources.gen.h", 'w') as f:
	f.write(generated_warning)
	f.write("extern " + var_type + var_prefix + var_name + ";")
