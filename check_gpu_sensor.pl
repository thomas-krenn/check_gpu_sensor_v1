#!/usr/bin/perl
use strict;
use warnings;
use nvidia::ml qw(:all);
use Getopt::Long;
use Class::Struct;

our $VERBOSITY = 0;
our $LASTERRORSTRING = '';#error messages of functions
our @DEVICE_LIST = ();
struct gpu_info_t => [
	deviceID => '$',
	productName => '$',
	nvmlMemoryInfo => '%',
	nvmlClockInfo => '%'
];

sub get_nvml_version;#forward decl

sub get_version{
	if(get_nvml_version() eq "NOK"){
		print "Error while fetching nvml version.\n";
		exit(3);		
	}
	return "check_nvml_gpu version 0.0 alpha 2011-11-12
Copyright (C) 2011 Thomas-Krenn.AG (written by Georg Schönberger)
Current update available at http://www.thomas-krenn.com/en/oss/nvml-plugin.
Your system is using nvml version: ".get_nvml_version();
}
sub get_usage{
	return "Usage:
check_nvml_gpu -H <hostname>
  [-f <NVML config file> | [-b] [-T <sensor type>] [-x <sensor id>] [-v 1|2|3]
  [-h] [-V]"
}

sub check_nvml_setup{
	#TODO Check for location of nvml library
	my $return = '';
	if(!(-e "/usr/lib32/libnvidia-ml.so")){
		$LASTERRORSTRING = "Nvml library not found on system";
		return "NOK";
	}
	else{
		return "OK";
	}
}
sub get_nvml_version{
	my ($return, $version);
	($return,$version) = nvmlSystemGetNVMLVersion();
	if($return == $NVML_SUCCESS){
		return $version;
	}
	else{
		return "NOK";
	}	
}
sub get_driver_version{
	my ($return, $version);
	($return, $version) = nvmlSystemGetDriverVersion();
	if($return == $NVML_SUCCESS){
		return $version;
	}
	else{
		$LASTERRORSTRING = nvmlErrorString($return);
		return "NOK";
	}	
}
sub get_device_count{
	my ($return, $count);
	($return, $count) = nvmlDeviceGetCount();
	if($return == $NVML_SUCCESS){
		return $count;
	}
	else{
		$LASTERRORSTRING = nvmlErrorString($return);
		return "NOK";
	}
}
sub get_device_clock{
	my $current_device = shift;
	my ($return, $handle) = nvmlDeviceGetHandleByIndex($current_device->deviceID);
	if($return != $NVML_SUCCESS){
		$LASTERRORSTRING = nvmlErrorString($return);
		return "NOK";
	}
	my %clock_hash;
	my $value;
	($return,$value) = nvmlDeviceGetClockInfo($handle,$NVML_CLOCK_GRAPHICS);
	if ($return != $NVML_SUCCESS){
		$LASTERRORSTRING = nvmlErrorString($return);
		return "NOK";
	}
	$clock_hash{"Graphics Clock"} = $value;
	($return,$value) = nvmlDeviceGetClockInfo($handle,$NVML_CLOCK_SM);
	if ($return != $NVML_SUCCESS){
		$LASTERRORSTRING = nvmlErrorString($return);
		return "NOK";
	}
	$clock_hash{"SM Clock"} = $value;
	($return,$value) = nvmlDeviceGetClockInfo($handle,$NVML_CLOCK_MEM);
	if ($return != $NVML_SUCCESS){
		$LASTERRORSTRING = nvmlErrorString($return);
		return "NOK"
	}
	$clock_hash{"Memory Clock"} = $value;
	return %clock_hash;
}


sub get_device_status{
	my $current_device = shift;
	my ($return, $handle, $value) = 0;
	($return, $handle) = nvmlDeviceGetHandleByIndex($current_device->deviceID);
	if($return != $NVML_SUCCESS){
		$LASTERRORSTRING = nvmlErrorString($return);
		return "NOK";
	}
	($return,$value) = nvmlDeviceGetName($handle);
	$current_device->productName($value);
	
	($return,$value) = nvmlDeviceGetMemoryInfo($handle);
	$current_device->nvmlMemoryInfo($value);
	
	$return = get_device_clock($current_device);
	$current_device->nvmlClockInfo($return) if($return ne "NOK");
			
	return $current_device;
}
sub get_device_stati{
	my $count = get_device_count();
	if($count eq "NOK"){
		print "Error: ".$LASTERRORSTRING.".\n";
		exit(3); 
	}
	if($count == 0){
		print "Error: No NVIDIA device found in current system.\n";
		exit(3);
	}
	print "Debug: Found $count devices in current system.\n";	
	
	for (my $i = 0; $i < $count; $i++){
		my $gpu = new gpu_info_t;
		$gpu->deviceID($i);
		$gpu = get_device_status($gpu);
		push(@DEVICE_LIST,$gpu);	
	}	
}
MAIN: {
	my ($verbosity,$nvml_host,$config_file,) = '';
	my @sensor_list = ();
	
	#Check for nvml installation
	my $result = '';
	if(($result = check_nvml_setup()) ne "OK"){
		print "Debug: Nvml setup check failed.\n";
		print "Error: ".$LASTERRORSTRING.".\n";
		exit(3);
	}
	#Initialize nvml library
	nvmlInit();
	$result = nvmlInit();
	if($result != $NVML_SUCCESS){
		print "Debug: NVML initialization failed.\n";
		print "Error: ".$LASTERRORSTRING.".\n";
		exit(3);
	}
	
	#Parse command line options
	if( !(Getopt::Long::GetOptions(
		'h|help'	=>
		sub{print get_version();
				print  "\n";
				print get_usage();
				print "\n";
				print get_help();
				exit(0);
		},
		'v|verbosity=i'	=>	\$verbosity,		
		'V|version'	=>
		sub{print get_version()."\n";
				exit(0);
		},
		'f|config-file=s' => \$config_file,
		'T|sensors=s' => \@sensor_list,
	))){
		print get_usage()."\n";
		exit(1);
	}
	if(@ARGV){
		#we don't want any unused command line arguments
		print get_usage()."\n";
		exit(3);
	}	

	if(($result = get_driver_version()) eq "NOK"){
		print "Debug: Get driver version failed.\n";
		print "Error: ".$LASTERRORSTRING.".\n";
		exit(3);
	}
	else{
		print "Debug: System NVIDIA driver version: ".$result."\n";
	}
	get_device_stati();
	print "Debug: Device list\n";
	foreach my $device (@DEVICE_LIST){
		print "Device ID: ".$device->deviceID."\n" if(defined ($device->deviceID));
		print "Model name: ".$device->productName."\n" if(defined ($device->productName));
		if(defined ($device->nvmlMemoryInfo)){
			my %hash = %{$device->nvmlMemoryInfo};
			foreach my $k (keys %hash) {
				print "$k: $hash{$k}\n";
			}
		}
		if(defined ($device->nvmlClockInfo)){
			my %hash = %{$device->nvmlClockInfo};
			foreach my $k (keys %hash) {
				print "$k: $hash{$k}\n";
			}
		}
	}
	
	

	exit(0);
	
	
#	
#	if(@sensor_list){
#		@sensor_list = split(/,/, join(',', @sensor_list));
#		print "@sensor_list";
#		exit(0);
#	}
#		
#	if($sensor_list[0] eq "temp"){
#		print "calling temp";
#	}
}
