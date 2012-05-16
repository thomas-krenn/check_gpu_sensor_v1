#!/usr/bin/perl
use strict;
use warnings;
use nvidia::ml qw(:all);
use Getopt::Long qw(:config no_ignore_case);#case sensitive
use Switch;

###############################################
# Global Variables in the current scope
###############################################
our $EXIT_CODE = 0; #Exit value of plugin
our $LASTERRORSTRING = ''; #Error messages of functions
our @DEVICE_LIST = (); #Array of GPUs in current system
# TODO Switch to hash and array as perf data cannot be assigned to a specific GPU
our @PERF_DATA = (); #Array of perf-data per GPU

#hash keys we don't want to have in PERF_DATA
our %EXCLUDE_LIST = (
	deviceHandle => '1',
	deviceID => '1',
	nvmlDevicePciInfo => '1',
	nvmlDeviceComputeMode => '1'
);

#warning and critical threshold levels
our %PERF_THRESHOLDS = (
	nvmlGpuTemperature => ['85','100'], #Temperature
	nvmlUsedMemory => ['95','99'], #Memory utilizaion
	nvmlDeviceFanSpeed => ['80','95'] #Fan speed
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
	return "check_gpu_sensor version 1.0 beta May 2012
Copyright (C) 2011-2012 Thomas-Krenn.AG (written by Georg Schönberger)
Current updates available via git repository git.thomas-krenn.com.
Your system is using NVIDIA driver version ".get_driver_version()." with
NVML version ".get_nvml_version();
}
sub get_usage{
	return "Usage:
check_gpu_sensor | [-T <sensor type>] [-w <list of warn levels>]
[-c <list of crit levels>] [-v|-vv|-vvv] [-h] [-V] [--show-na]"
}
sub get_help{
	return "
  [-T <sensor type>]
       limit sensors to query based on NVML sensor types.
       Examples for GPU sensor types are 'nvmlGpuTemperature',
       'nvmlUsedMemory','nvmlDeviceFanSpeed'
  [-w <list of warning thresholds>]
       Change the default warning levels. The order of the levels
       is the following:
       -nvmlGpuTemperature
       -nvmlUsedMemory
       -nvmlDeviceFanSpeed
       Levels that should stay default get a 'd' assigned.
       Example:
           check_gpu_sensor.pl -w '75,d,d' 
       This changes the warning level for the temperature.
  [-c <list of critical thresholds>]
       Change the default critical levels. The order of the levels
       is the same as for the warning levels.
       Levels that should stay default get a 'd' assigned.
       Example:
           check_gpu_sensor.pl -c '100,d,d' 
       This changes the critical level for the temperature.  		
  [-v <Verbose Level>]
       be verbose
         (no -v) .. single line output
         -v ..... single line output with additional details for warnings
         -vv ..... multi line output, also with additional details for warnings
         -vvv ..... normal output, then debugging output, followed by normal multi line output
  [-h]
       show this help
  [-V]
       show version information
  [--show-na]
       show sensors with value equal to N/A (means not available)";
}


sub check_nvml_setup{
	#TODO Check for location of nvml library
	my $return = '';
	if(!(-e "/usr/lib32/libnvidia-ml.so") &&
		!(-e "/usr/lib32/nvidia-current/libnvidia-ml.so") &&
		!(-e "/usr/lib/nvidia-current/libnvidia-ml.so") &&
		!(-e "/usr/lib/libnvidia-ml.so")){
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
# They also generate status outputs and verbose information
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
#Prints all values of a given hash
#If every value of the hash is N/A, the string
#N/A is returned
sub print_hash{
	my $hash_ref = shift;
	my $show_na = shift;
	my $string = "";
	my $is_na = 1;
	
	foreach my $k (keys %{$hash_ref}) {
		if($hash_ref->{$k} ne "N/A"){
			$is_na = 0;
		}
		#only print N/A sensors if show all is given
		if(!(defined $show_na) && $hash_ref->{$k} eq "N/A"){
			next;
		}
		if(ref($hash_ref->{$k}) eq "SCALAR"){
			$string .= "\t$k: $$hash_ref->{$k}\n";
		}
		else{
			$string .= "\t$k: $hash_ref->{$k}\n";	
		}		
	}
	#if all values are N/A, return this
	if($is_na){
		return "N/A";
	}
	else{
		return $string;
	}
}
#Print the value of the status hash
sub get_hash_values{
	my $hash_ref = shift;#reference to device hash
	my $show_na = shift;
	my $string = "";
	my $is_na = 1;
	
	if(exists $hash_ref->{'Error'}){
		$string .= "Error: ".$hash_ref->{'Error'}."\n";
		return $string;
	}
	foreach my $k (keys %{$hash_ref}) {
		if($k eq "deviceHandle"){
			next;#we don't want to print driver handles
		}
		#only print N/A sensors if show all is given
		if(!(defined $show_na) && $hash_ref->{$k} eq "N/A"){
			next;
		}
		#if we found a hash, call the print_hash function
		#if all values of a hash are N/A, the hash itself gets
		#the string N/A assigned
		if(ref($hash_ref->{$k}) eq "HASH"){
				my $hash_string = print_hash($hash_ref->{$k},$show_na);
				if($hash_string eq "N/A"){
					if(defined $show_na){
						$string .= "-$k: $hash_string\n";
					}
				}
				else{
					$string .= "-$k\n";
					$string .= $hash_string;
				}
		}
		elsif(ref($hash_ref->{$k}) eq "SCALAR"){
			$string .= "-$k: $$hash_ref->{$k}\n";
		}
		else{
			$string .= "-$k: $hash_ref->{$k}\n";	
		}
	}
	return $string;
	
}
#Form a status string with warning, crit sensor values
#or performance data followed by their thresholds
sub get_status_string{
	my $level = shift;
	my $curr_sensors = shift;
	my $verbosity = shift;
	my $status_string = "";

	if($level ne "Warning" && $level ne "Critical"
		&& $level ne "Performance"){
		return;
	}
	if($level eq "Warning"){
		$curr_sensors = $curr_sensors->[1];
	}
	if($level eq "Critical"){
		$curr_sensors = $curr_sensors->[2];
	}
	my $i = 1;
	#Collect performance data of warn and crit sensors
	if($level eq "Warning" || $level eq "Critical"){
		if(@$curr_sensors){
			foreach my $sensor (@$curr_sensors){
				$status_string .= "[".$sensor." = ".$level;
				if($verbosity){
					$status_string .= " (".$PERF_DATA[0]->{$sensor}.")";	
				}
				$status_string .= "]";
				if($i != @$curr_sensors){
					$status_string .= " ";#print a space except at the end
				}
				$i++;
			}
		}
	}
	#Collect performance values followed by thresholds
	if($level eq "Performance"){
		foreach my $k (keys %$curr_sensors){
			$status_string .= $k."=".$curr_sensors->{$k};
			#print warn and crit thresholds
			if(exists $PERF_THRESHOLDS{$k}){
				$status_string .= ";".$PERF_THRESHOLDS{$k}[0];
				$status_string .= ";".$PERF_THRESHOLDS{$k}[1].";";
			}
			if($i != (keys %$curr_sensors)){
				$status_string .= " ";
			}
			$i++;
		}	
	}
	return $status_string;
}
sub get_verbose_string{
	my $verbosity = shift;
	my $device = shift;
	my $show_na = shift;
	my $status_string = "";
	
	if($verbosity == 3){
		$status_string .= "------------- begin of debug output (-vvv is set): ------------\n";
		$status_string .= "Nvidia Driver Version: ".get_driver_version()."\n";
		$status_string .= "Number of GPUs in system: ".@DEVICE_LIST."\n";
		foreach my $g (@DEVICE_LIST){
			$status_string .= "\t-".$g->{'productName'}."\n";
		}
		$status_string .= "----Called sensors (incl. N/A)----\n";
		$status_string .= get_hash_values($device,1);
	}
	if($verbosity == 3){
		$status_string .= "------------- end of debug output ------------\n";
	}
	if($verbosity == 2 || $verbosity == 3){
		$status_string .= get_hash_values($device,$show_na)
	}
	return $status_string;
}

#Check a hash for performance data
sub check_hash_for_perf{
	my $hash_ref = shift;
	my $perf_data_ref = shift;
	my @sensor_list = @{(shift)};
	my %hash = %$hash_ref;
		
	if(exists $hash{'Error'}){
		print "Status: ".$hash{'Error'}."\n";
		return;
	}	
	foreach my $k (@sensor_list) {
		#we don't want to print values present in exclude list
		if(exists $EXCLUDE_LIST{$k}){
			next;
		}
		if(ref($hash{$k}) eq "HASH"){
			#the param sensor_list is switched to the hash keys for the next call of check_hash
			my @key_list = keys %{$hash{$k}};
			$perf_data_ref = check_hash_for_perf($hash{$k},$perf_data_ref,\@key_list);
		}
		elsif(ref($hash{$k}) eq "SCALAR"){
			#found a ref to a numeric value
			#deref it and push it to hash
			$perf_data_ref->{$k} = ${$hash{$k}};
		}
		elsif ($hash{$k} =~ /^[-+]?[0-9]*\.?[0-9]+$/ ){
				#found a numeric value, push it to the given hash reference
				$perf_data_ref->{$k} = sprintf("%.2f", $hash{$k});
		}
	}
	return $perf_data_ref;
}

###############################################
# System specific functions 
# They are used to collect information about the current system
###############################################
sub get_nvml_version{
	#Working since 3.295.41
	my $version = get_driver_version();
	$version =~ /(\d+)\.(\d+)/;
	if($1 >= 295){
		my ($return, $version) = nvmlSystemGetNVMLVersion();
		if($return == $NVML_SUCCESS){
			return $version;
		}
	}
	else{
		return "not yet supported";
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
sub get_device_memory{
	my $current_ref = shift;
	my %current_device = %$current_ref;
	my $memory_hash;
	my $used_memory = -1;
	my ($return,$value);
	
	($return,$value) = nvmlDeviceGetMemoryInfo($current_device{'deviceHandle'});
	$memory_hash = (handle_error($return,$value));
	if($memory_hash eq "N/A"){
		$used_memory = "N/A";
	}
	else{
		$used_memory = 100 * ($memory_hash->{'used'}) / ($memory_hash->{'total'});
	}
	return $used_memory;	
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
	
	$return = get_device_memory($current_ref);
	$current_device{'nvmlUsedMemory'} = $return;
			
	return \%current_device;
}
###############################################
# Overall device functions 
# They collect functions for all devices in the current system
###############################################
sub get_all_device_status{
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

#parses the device hashes and collects the perf data (only numeric values)
#into arrays
sub collect_perf_data{
	
	my $sensor_list_ref = shift;
	my @sensor_list = ();
		
	foreach my $device (@DEVICE_LIST){
		#fetch the desired sensors
		if(@$sensor_list_ref){
			@sensor_list = split(/,/, join(',', @$sensor_list_ref));
		}
		else{
			#if no sensor is given via -T, we dump all
			@sensor_list = keys %$device;
		}
		my %dev_perf_data = ();
		my $dev_data_ref = \%dev_perf_data;
		$dev_data_ref = check_hash_for_perf($device,$dev_data_ref,\@sensor_list);
		push(@PERF_DATA,$dev_data_ref);#push device perf data to system array
	}	
}
#checks if the given performance data is in its rangens
sub check_perf_threshold{
	
	my @warn_list = @{(shift)};
	my @crit_list = @{(shift)};
	my @status_level = ("OK");
	my @warn_level = ();#warning sensors
	my @crit_level = ();#crit sensors
	
	my $i = 0;
	if(@warn_list){
		@warn_list = split(/,/, join(',', @warn_list));
		for ($i = 0; $i < @warn_list; $i++){
			#everything, except that values that sould stay default, get new values
			#e.g. -w d,15,60 changes the warning level for sensor 2 and 3 but not for 1
			if($warn_list[$i] ne 'd'){
				switch($i){
					case 0 {$PERF_THRESHOLDS{'nvmlGpuTemperature'}[0] = $warn_list[$i]};
					case 1 {$PERF_THRESHOLDS{'nvmlUsedMemory'}[0] = $warn_list[$i]};
					case 2 {$PERF_THRESHOLDS{'nvmlDeviceFanSpeed'}[0] = $warn_list[$i]};
				}					
			}		
		}			
	}
	if(@crit_list){
		@crit_list = split(/,/, join(',', @crit_list));
		for ($i = 0; $i < @crit_list; $i++){
			if($crit_list[$i] ne 'd'){
				switch($i){
					case 0 {$PERF_THRESHOLDS{'nvmlGpuTemperature'}[1] = $crit_list[$i]};
					case 1 {$PERF_THRESHOLDS{'nvmlUsedMemory'}[1] = $crit_list[$i]};
					case 2 {$PERF_THRESHOLDS{'nvmlDeviceFanSpeed'}[1] = $crit_list[$i]};
				}
			}		
		}			
	}
	#TODO Change this to multiple devices, only the first one is used for now
	my $perf_hash = $PERF_DATA[0];
	foreach my $k (keys %$perf_hash){
		if(exists $PERF_THRESHOLDS{$k}){
			#warning level
			if($perf_hash->{$k} >= $PERF_THRESHOLDS{$k}[0]){
				$status_level[0] = "Warning";
				push(@warn_level,$k);
			}
			#critival level
			if($perf_hash->{$k} >= $PERF_THRESHOLDS{$k}[1]){
				$status_level[0] = "Critical";
				pop(@warn_level);#as it is critical, remove it from warning
				push(@crit_level,$k);
			}
		}		
	}
	push(@status_level,\@warn_level);
	push(@status_level,\@crit_level);
	
	return \@status_level;	
}
###############################################
# Main function
# Command line processing and device status collection
###############################################
MAIN: {
	my ($nvml_host,$config_file,$show_na,$show_default) = '';
	my @sensor_list = ();#query a specific sensor
	my @warn_threshold = ();#change thresholds for performance data
	my @crit_threshold = ();
	my $verbosity = 0;
	
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
				print get_help()."\n";
				exit(0);
		},
		'V|version'	=>
		sub{print get_version()."\n";
				exit(0);
		},
		'v|verbosity'	=>	\$verbosity,
		'vv'			=> sub{$verbosity=2},
		'vvv'			=> sub{$verbosity=3},
		'T|sensors=s' => \@sensor_list,
		'w|warning=s' => \@warn_threshold,
		'c|critical=s' => \@crit_threshold,
		'show-na'	=> \$show_na,
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
	get_all_device_status();
	#TODO Is the sensor list only for performance data valid?
	collect_perf_data(\@sensor_list);
	my $status_level;
	$status_level = check_perf_threshold(\@warn_threshold,\@crit_threshold);
	#check return values of threshold function
	if($status_level->[0] eq "Critcal"){
		$EXIT_CODE = 2;#Critical
	}
	if($status_level->[0] eq "Warning"){
		$EXIT_CODE = 1;#Warning
	}
	print $status_level->[0]." - ".$DEVICE_LIST[0]->{'productName'}." ";
	print get_status_string("Critical",$status_level,$verbosity);
	print get_status_string("Warning",$status_level,$verbosity);
	print "|";
	print get_status_string("Performance",$PERF_DATA[0]);
	print "\n".get_verbose_string($verbosity,$DEVICE_LIST[0],$show_na);

	exit($EXIT_CODE);	
}
