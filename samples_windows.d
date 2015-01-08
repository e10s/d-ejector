import ejector;

void main(){
	// Assign a drive letter and test the drive.
	auto e1 = Ejector("f");
	e1.ejectable;

	// Try to get an automatically selected drive open.
	auto e2 = Ejector();
	e2.open();

	// Search for all ejectable drives and try to get them open/closed.
	import std.algorithm, std.ascii;
	foreach(e; uppercase.map!(a => Ejector(cast(char)a)).filter!(a => a.ejectable)){
		e.open();  // If e is equivalent to e2 and you have not closed the drive related to it, nothing will occur.
		e.closed();
	}
}
