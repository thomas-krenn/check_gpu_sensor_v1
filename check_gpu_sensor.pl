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
	deviceHandle => '$',
	productName => '$',
	nvmlMemoryInfo => '%',
	nvmlClockInfo => '%',
	nvmlDevicePciInfo => '%',
	nvmlDeviceComputeMode => '$',
	nvmlDeviceFanSpeed => '$',
	nvmlGpuTemperature => '$',
	nvmlDeviceUtilizationRates => '%'
];

sub get_nvml_version;#forward decl
sub handle_error{
	my $return = $_[0];
	my $value = $_[1];
	my $is_hash = $_[2];
	
	if($return == $NVML_SUCCESS){
		return $value;
	}
	else{
		if($return == $NVML_ERROR_NOT_SUPPORTED){
			if(defined $is_hash){
				my %error_pair = ('Error',"N/A");				
				return \%error_pair;
			}			
			return "N/A";	
		}
		else{
			if(defined $is_hash){
				my %error_pair = ('Error',nvmlErrorString($return));				
				return \%error_pair;
			}	
			return nvmlErrorString($return);
		}
	}	
}
sub print_hash_values{
	my %hash = %{$_[0]};
	if(exists $hash{'Error'}){
		print "Status: ".$hash{'Error'}."\n";
		return;
	}
	foreach my $k (keys %hash) {
		print "\t$k: $hash{$k}\n";
	}
}
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
	if(!(-e "/usr/lib32/libnvidia-ml.so") &&
		!(-e "/usr/lib32/nvidia-current/libnvidia-ml.so")){
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
	my $current_ref = shift;
	my %current_device = %$current_ref;
	my %clock_hash;
	my ($return,$value);
	($return,$value) = nvmlDeviceGetClockInfo($current_device{'deviceHandle'},$NVML_CLOCK_GRAPHICS);
	$clock_hash{'Graphics Clock'} = handle_error($return,$value);
	
	($return,$value) = nvmlDeviceGetClockInfo($current_device{'deviceHandle'},$NVML_CLOCK_SM);
	$clock_hash{'SM Clock'} = handle_error($return,$value);
	
	($return,$value) = nvmlDeviceGetClockInfo($current_device{'deviceHandle'},$NVML_CLOCK_MEM);
	$clock_hash{'Memory Clock'} = handle_error($return,$value);
	
	return \%clock_hash;
}
sub get_device_status{
	my $current_ref = shift;
	my %current_device = %$current_ref;
	my ($return, $value) = 0;
	
	($return,$value) = nvmlDeviceGetName($current_device{'deviceHandle'});
	$current_device{'productName'} = (handle_error($return,$value));
	
	($return,$value) = nvmlDeviceGetComputeMode($current_device{'deviceHandle'});
	$current_device{'nvmlDeviceComputeMode'} = (handle_error($return,$value));	
	
	($return,$value) = nvmlDeviceGetFanSpeed($current_device{'deviceHandle'});
	$current_device{'nvmlDeviceFanSpeed'} = (handle_error($return,$value));
	
	($return,$value) = nvmlDeviceGetTemperature($current_device{'deviceHandle'},$NVML_TEMPERATURE_GPU);
	$current_device{'nvmlGpuTemperature'} = (handle_error($return,$value));
	
	($return,$value) = nvmlDeviceGetMemoryInfo($current_device{'deviceHandle'});
	$current_device{'nvmlMemoryInfo'} = (handle_error($return,$value));
	
	($return,$value) = nvmlDeviceGetPciInfo($current_device{'deviceHandle'});
	$current_device{'nvmlDevicePciInfo'} = (handle_error($return,$value));
	
	($return,$value) = nvmlDeviceGetUtilizationRates($current_device{'deviceHandle'});
	$current_device{'nvmlDeviceUtilizationRates'} = (handle_error($return,$value));
	
	$return = get_device_clock($current_ref);	
	$current_device{'nvmlClockInfo'} = $return;	
			
	return \%current_device;
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
		my %gpu_h;
		my $gpu_ref = \%gpu_h;
		$gpu_h{'deviceID'} = $i;		
		my ($return, $handle) = nvmlDeviceGetHandleByIndex($gpu_h{'deviceID'});
		if($return != $NVML_SUCCESS){
			print "Error: Cannot get handle for device: ".nvmlErrorString($return)."\n";
			next;
		}
		$gpu_h{'deviceHandle'} = $handle;			
		$gpu_ref = get_device_status(\%gpu_h);
		push(@DEVICE_LIST,$gpu_ref);	
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
		foreach my $k (keys %$device) {
			if($k eq "deviceHandle"){
				next;
			}
			if(ref($device->{$k}) eq "HASH"){
				print "$k:\n";
				print_hash_values($device->{$k})
			}
			elsif(ref($device->{$k}) eq "SCALAR"){
				print "$k: $$device->{$k}\n";
			}
			else{
				print "$k: $device->{$k}\n";	
			}
			
		}
	}
	exit(0);	
}
