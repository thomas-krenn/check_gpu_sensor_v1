#!/usr/bin/perl
use strict;
use warnings;
use Switch;
use nvidia::ml qw(:all);
use Getopt::Long;

our $lastErrorString = '';#error messages of functions

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
		$lastErrorString = "Nvml library not found on system";
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
		$lastErrorString = nvmlErrorString($return);
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
		$lastErrorString = nvmlErrorString($return);
		return "NOK";
	}
}
sub get_device_status{
	my $device_id = $_[0];
	my ($return, $handle);
	($return, $handle) = nvmlDeviceGetHandleByIndex($device_id);
	if($return != $NVML_SUCCESS){
		$lastErrorString = nvmlErrorString($return);
		return "NOK";
	}
	
	
}
sub get_device_stati{
	my $count = get_device_count();
	if($count eq "NOK"){
		print "Error: ".$lastErrorString.".\n";
		exit(3); 
	}
	if($count == 0){
		print "Error: No NVIDIA device found in current system.\n";
		exit(3);
	}
	print "Debug: Found $count devices in current system.\n";
		
	
}
MAIN: {
	my ($verbosity,$nvml_host,$config_file,) = '';
	my @sensor_list = ();
	
	#Check for nvml installation
	my $result = '';
	if(($result = check_nvml_setup()) ne "OK"){
		print "Debug: Nvml setup check failed.\n";
		print "Error: ".$lastErrorString.".\n";
		exit(3);
	}
	#Initialize nvml library
	nvmlInit();
	$result = nvmlInit();
	if($result != $NVML_SUCCESS){
		print "Debug: NVML initialization failed.\n";
		print "Error: ".$lastErrorString.".\n";
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
		print "Error: ".$lastErrorString.".\n";
		exit(3);
	}
	else{
		print "Debug: System NVIDIA driver version: ".$result."\n";
	}
	get_device_stati();
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
