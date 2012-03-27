#!/usr/bin/perl
use strict;
use warnings;
use nvidia::ml qw(:all);
use Getopt::Long;

###############################################
# Global Variables in the current scope
###############################################
our $VERBOSITY = 0; #The current verbosity level
our $LASTERRORSTRING = ''; #Error messages of functions
our @DEVICE_LIST = (); #Array of GPUs in current system
our %EXCLUDE_LIST = (
	deviceHandle => '1',
	deviceID => '1',
	nvmlDevicePciInfo => '1'
);

###############################################
# Plugin specific functions
# They return help messages and version information
###############################################
sub get_version{
	if(get_driver_version() eq "NOK"){
		print "Error while fetching nvidia driver version: $LASTERRORSTRING\n";
		exit(3);		
	}
	return "check_nvml_gpu version 0.0 alpha 2011-11-12
Copyright (C) 2011 Thomas-Krenn.AG (written by Georg Schönberger)
Current update available at http://www.thomas-krenn.com/en/oss/nvml-plugin.
Your system is using nvidia driver version: ".get_driver_version();
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
###############################################
# Helper functions 
# They check for errors and print several structs
###############################################

# Checking for errors returned by the nvml library
# If a functionality is not supported "N/A" is returned
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
				foreach my $k (keys %$value){
					$value->{$k} = "N/A";					
				}
				return $value;
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

#Print the value of the status hash
sub print_hash_values{
	my %hash = %{$_[0]};
	if(exists $hash{'Error'}){
		print "Status: ".$hash{'Error'}."\n";
		return;
	}
	foreach my $k (keys %hash) {
		if(ref($hash{$k}) eq "HASH"){
				print "$k:\n";
				print_hash_values($hash{$k})
		}
		else{
			print "\t$k: $hash{$k}\n";
		}
	}
}

#Check a hash for performance data
sub check_hash_for_perf{
	my $hash_ref = shift;
	my $perf_data_ref = shift;
	my %hash = %$hash_ref;
	
	if(exists $hash{'Error'}){
		print "Status: ".$hash{'Error'}."\n";
		return;
	}	
	foreach my $k (keys %hash) {
		if(ref($hash{$k}) eq "HASH"){
			check_hash_for_perf($hash{$k},$perf_data_ref);
		}
		elsif(ref($hash{$k}) eq "SCALAR"){
			#found a ref to a numeric value
			#deref it and push it to hash
			push(@$perf_data_ref,"$k:${$hash{$k}}");
		}
		else{
			if ($hash{$k} =~ /^[+-]?\d+$/ ){
				#found a numeric value, push it to the given hash reference
				push(@$perf_data_ref,"$k:$hash{$k},");
			}
		}
	}
	return $perf_data_ref;
}

###############################################
# System specific functions 
# They are used to collect information about the current system
###############################################
sub get_nvml_version{
	#TODO Check if nvml version can be used? Currently not working with bindings under driver 280
	my ($return, $version);
	nvmlSystemGetNVMLVersion();
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
###############################################
# Device specific functions 
# They are used to query parameters from a device
###############################################
sub get_device_clock{
	my $current_ref = shift;
	my %current_device = %$current_ref;
	my %clock_hash;
	my ($return,$value);
	($return,$value) = nvmlDeviceGetClockInfo($current_device{'deviceHandle'},$NVML_CLOCK_GRAPHICS);
	$clock_hash{'graphicsClock'} = handle_error($return,$value);
	
	($return,$value) = nvmlDeviceGetClockInfo($current_device{'deviceHandle'},$NVML_CLOCK_SM);
	$clock_hash{'SMClock'} = handle_error($return,$value);
	
	($return,$value) = nvmlDeviceGetClockInfo($current_device{'deviceHandle'},$NVML_CLOCK_MEM);
	$clock_hash{'memClock'} = handle_error($return,$value);
	
	return \%clock_hash;
}
sub get_device_inforom{
	my $current_ref = shift;
	my %current_device = %$current_ref;
	my %inforom_hash;
	my ($return,$value);
	($return,$value) = nvmlDeviceGetInforomVersion($current_device{'deviceHandle'},$NVML_INFOROM_OEM);
	$inforom_hash{'OEMinforom'} = handle_error($return,$value);
	
	($return,$value) = nvmlDeviceGetInforomVersion($current_device{'deviceHandle'},$NVML_INFOROM_ECC);
	$inforom_hash{'ECCinforom'} = handle_error($return,$value);
	
	($return,$value) = nvmlDeviceGetInforomVersion($current_device{'deviceHandle'},$NVML_INFOROM_POWER);
	$inforom_hash{'Powerinforom'} = handle_error($return,$value);
	
	return \%inforom_hash;
}
sub get_device_ecc{
	my $current_ref = shift;
	my %current_device = %$current_ref;
	my %ecc_hash;
	my ($return,$value,$value1);
	($return,$value,$value1) = nvmlDeviceGetEccMode($current_device{'deviceHandle'});
	$ecc_hash{'currentECCMode'} = handle_error($return,$value);
	$ecc_hash{'pendingECCMode'} = handle_error($return,$value1);
	
	($return,$value) = nvmlDeviceGetDetailedEccErrors($current_device{'deviceHandle'},$NVML_SINGLE_BIT_ECC,$NVML_VOLATILE_ECC);
	$ecc_hash{'volatileSingle'} = handle_error($return,$value);
	
	($return,$value) = nvmlDeviceGetDetailedEccErrors($current_device{'deviceHandle'},$NVML_DOUBLE_BIT_ECC,$NVML_VOLATILE_ECC);
	$ecc_hash{'volatileDouble'} = handle_error($return,$value);
	
	($return,$value) = nvmlDeviceGetDetailedEccErrors($current_device{'deviceHandle'},$NVML_SINGLE_BIT_ECC,$NVML_AGGREGATE_ECC);
	$ecc_hash{'aggregateSingle'} = handle_error($return,$value);
	
	($return,$value) = nvmlDeviceGetDetailedEccErrors($current_device{'deviceHandle'},$NVML_DOUBLE_BIT_ECC,$NVML_AGGREGATE_ECC);
	$ecc_hash{'aggregateDouble'} = handle_error($return,$value);
	
	($return,$value) = nvmlDeviceGetTotalEccErrors($current_device{'deviceHandle'},$NVML_SINGLE_BIT_ECC,$NVML_VOLATILE_ECC);
	$ecc_hash{'volatileSingleTotal'} = handle_error($return,$value);
	
	($return,$value) = nvmlDeviceGetTotalEccErrors($current_device{'deviceHandle'},$NVML_DOUBLE_BIT_ECC,$NVML_VOLATILE_ECC);
	$ecc_hash{'volatileDoubleTotal'} = handle_error($return,$value);
	
	($return,$value) = nvmlDeviceGetTotalEccErrors($current_device{'deviceHandle'},$NVML_SINGLE_BIT_ECC,$NVML_AGGREGATE_ECC);
	$ecc_hash{'aggregateSingleTotal'} = handle_error($return,$value);
	
	($return,$value) = nvmlDeviceGetTotalEccErrors($current_device{'deviceHandle'},$NVML_DOUBLE_BIT_ECC,$NVML_AGGREGATE_ECC);
	$ecc_hash{'aggregateDoubleTotal	'} = handle_error($return,$value);
	
	return \%ecc_hash;
}
sub get_device_power{
	my $current_ref = shift;
	my %current_device = %$current_ref;
	my %power_hash;
	my ($return,$value);
	
	#TODO Check if GPU supports power infos (inforom version > 0)
	($return,$value) = nvmlDeviceGetPowerManagementMode($current_device{'deviceHandle'});
	$power_hash{'pwManagementMode'} = handle_error($return,$value);
	
	return \%power_hash;
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
	
	$return = get_device_inforom($current_ref);	
	$current_device{'nvmlDeviceInforom'} = $return;
	
	$return = get_device_ecc($current_ref);	
	$current_device{'nvmlDeviceEccInfos'} = $return;
	
	$return = get_device_power($current_ref);	
	$current_device{'nvmlDevicePowerInfos'} = $return;
			
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
	#for each device fetch a driver handle and call
	#the function to get the device status informations
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
		print "Error: ".nvmlErrorString($result).".\n";
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
		print "Error: driver version - ".$LASTERRORSTRING.".\n";
		exit(3);
	}
	
	#Collect the informations about the devices in the system
	get_device_stati();
#	print "Debug: Device list\n";
#	foreach my $device (@DEVICE_LIST){
#		foreach my $k (keys %$device) {
#			if($k eq "deviceHandle"){
#				next;#we don't want to print driver handles
#			}
#			if(ref($device->{$k}) eq "HASH"){
#				print "$k:\n";
#				print_hash_values($device->{$k})
#			}
#			elsif(ref($device->{$k}) eq "SCALAR"){
#				print "$k: $$device->{$k}\n";
#			}
#			else{
#				print "$k: $device->{$k}\n";	
#			}
#			
#		}
#	}
	my @perf_data = ("Performance: ");
	my $perf_data_ref = \@perf_data;
	
	#fetch the desired sensors
	if(!@sensor_list){
		@sensor_list = split(/,/, join(',', @sensor_list));
	}
		
	#Check for performance values
	foreach my $device (@DEVICE_LIST){
		foreach my $k (keys %$device) {
			#we don't want to print values present in exclude list
			if(exists $EXCLUDE_LIST{$k}){
				next;
			}
			#if a sensor list is given we only print these ones
			if(@sensor_list && (grep(/$k/,@sensor_list)== 0)){
				next;
			}
			#if the current key points to a hash reference, check
			#it for performance values	
			if(ref($device->{$k}) eq "HASH"){
				$perf_data_ref = check_hash_for_perf($device->{$k},$perf_data_ref);
			}
			elsif(ref($device->{$k}) eq "SCALAR"){
				push(@$perf_data_ref,"$k:${$device->{$k}},");
			}
			else{
				#check if it is a number
				if ($device->{$k} =~ /^[+-]?\d+$/ ){
					push(@$perf_data_ref,"$k:$device->{$k},");
				}
			}
		}
	}
	#use Data::Dumper;
	#print Dumper(\@perf_data);
	print "OK|gpu_temp=$DEVICE_LIST[0]->{nvmlGpuTemperature};\@80:90;\@90:100";
	exit(0);	
}
