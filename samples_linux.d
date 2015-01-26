import ejector;

void main(){
	// Assign a device and test the drive.
	auto e1 = Ejector("/dev/sr0");
	e1.ejectable;

	// Try to get the default "/dev/cdrom" open.
	auto e2 = Ejector();
	e2.open();

	// Search for all ejectable drives and try to toggle open/closed.
	import std.algorithm, std.stdio, std.typecons;
	foreach(e; ["/dev/stdin", "/dev/null", "/dev/dvd", "/no/such/device"].
		map!(a => tuple(a, Ejector(a))).filter!(a => a[1].ejectable)){
		writeln(e[0] ~ " is ejectable!");
		auto status = e[1].status;
		if(status == TrayStatus.OPEN){
			e[1].closed();
		}
		else if(status == TrayStatus.CLOSED){
			e[1].open();
		}
	}
}
