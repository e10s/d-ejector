import ejector;

void main(){
	// Assign a drive letter and test the drive.
	auto e1 = Ejector("f");
	e1.ejectable;

	// Try to get an automatically selected drive open.
	auto e2 = Ejector();
	e2.open();

	// Search for all ejectable drives and try to toggle open/closed.
	import std.algorithm, std.ascii;
	foreach(e; uppercase.map!(a => Ejector(cast(char)a)).filter!(a => a.ejectable)){
		auto status = e.status;
		if(status == TrayStatus.OPEN){
			e.closed();
		}
		else if(status == TrayStatus.CLOSED){
			e.open();
		}
	}
}
