import ejector;

void main(){
	// Assign a device and test the drive.
	auto e1 = Ejector("/dev/sr0");
	e1.ejectable;

	// Try to get the default "/dev/cdrom" open.
	auto e2 = Ejector();
	e2.open();

	// Search for all ejectable drives and try to get them open/closed.
	import std.algorithm, std.stdio, std.typecons;
	foreach(e; ["/dev/stdin", "/dev/null", "/dev/dvd", "/no/such/device"].
		map!(a => tuple(a, Ejector(a))).filter!(a => a[1].ejectable)){
		writeln(e[0] ~ " is ejectable!");
		e[1].open();  // If e[1] is equivalent to e2 and you have not closed the drive related to it, nothing will occur.
		e[1].closed();
	}
}
