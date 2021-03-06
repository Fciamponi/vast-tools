#!/usr/bin/env perl

use FindBin;
use lib "$FindBin::Bin/../lib";
use FuncBasics qw(:all);

# This script parses the bowtie output of the EXSK (A priori, simplex exon skipping) mapping.
use Getopt::Long;

use Cwd qw(abs_path);
$cwd = abs_path($0);
($dir)=$cwd=~/(.+)\/bin/;

my $dbDir;
my $sp;
my $length;
my $root;
my $strandaware=0;
my $print_EEJs=0;

GetOptions("dbDir=s" => \$dbDir, "sp=s" => \$sp, "readLen=i" => \$length, 
	   "root=s" => \$root, "s" => \$strandaware, "ec" => \$print_EEJs);

my $mapcorr_fileswitch=""; if($strandaware){$mapcorr_fileswitch="-SS"}

### parses the general information for the events
open (TEMPLATE, "$dbDir/TEMPLATES/$sp.EXSK.Template.1.txt") || die "No SIMPLE EXSK Template for $sp\n";
while (<TEMPLATE>){
    chomp;
    @t=split(/\t/);
    $event=$t[3];
    $pre_data{$t[3]}=join("\t",@t[0..11]);
    $COMPLEX{$t[3]}=$t[12];
    $NAME{$t[3]}=$t[13];
}
close TEMPLATE;

### Loads mappability information
open (MAPPABILITY, "$dbDir/FILES/EXSK-$length-gDNA${mapcorr_fileswitch}.eff") || die "No Mappability for $sp\n";
while (<MAPPABILITY>){
    chomp;
    @t=split(/\t/);
    ($event,$eej)=$t[0]=~/(.+)_(.+?_\d+?_\d+?_\d+)/;
    $eff{$event}{$eej}=$t[1];
}
close MAPPABILITY;

#### parses the bowtie output file for the EEJ sequences
while (<STDIN>){
    chomp;
    @t=split(/\t/);

    # this is to get the actual read name to avoid doublecounting in a sorted output
    ($read)=$t[0]=~/(.+)\-/;
    $read=$t[0] if !$read;

    ($event,$eej)=$t[2]=~/(.+)_(.+?_\d+?_\d+?_\d+)/; #gets exon-exon junction (eej) info
    
    if ($event ne $previous_event || $read ne $previous_read){	#avoid multiple counting
	$read_count{$event}{$eej}++;
	$POS{$event}{$eej}{$t[3]}++;
    }

    #keeps a 1-line memmory in the loop
    $previous_read=$read; 
    $previous_event=$event;
}
#close $I;

open (EEJ, ">to_combine/$root.eejEX") if $print_EEJs;
open (O, ">to_combine/$root.exskX") || die "Cannot open EXSK output"; #file with PSI and read counts per event.
### Temporary output format needed for Step 2
print O "Ensembl_ID\tA_coord\tStrand\tEvent_ID\tFullCoord\tType\tLength\tC1_coord\tC2_coord\tLength_Int1\tLength_Int2\t3n\t";
print O "PSI\tReads_exc\tReads_inc1\tReads_inc2\tSum_of_reads\t.\tComplexity\tCorrected_Exc\tCorrected_Inc1\tCorrected_Inc2\t.\t.\t.\tGene_name\n";

### Calculating PSIs
$cle=$length-15; #read length for correction.
foreach $event (sort (keys %eff)){
    $eI1=$eI2=$eE=$I1=$I2=$E=$rI1=$rI2=$rE=""; # empty temporary variables in each loop
    
    if(!defined($pre_data{$event})){next;}	# skip events coming from "Mappability information" (%eff) which are not in Template.1.txt (%pre_data)
						# This filter was necessary after introducing the strandaware mode, because being strandaware we have available some
						# events more which were/are not avaibale in strand-unaware mode, but Template.1.txt contains information for events
						# in strand-unaware mode only. 

    foreach $eej (sort (keys %{$eff{$event}})){
	($exons)=$eej=~/(.+?)\_.+?\_.+?\_\d+/;
	
	### prints EEJ counts if specified
	if ($print_EEJs){
	    $p_p="";
	    foreach $POS (sort {$a<=>$b}(keys %{$POS{$event}{$eej}})){
		$p_p.="$POS:$POS{$event}{$eej}{$POS},";
	    }
	    chop($p_p);
	    print EEJ "$event\t$eej\t$read_count{$event}{$eej}\t$eff{$event}{$eej}\t$p_p\n";
	}
	
	if ($eff{$event}{$eej}>0){
	    # corrected count for I1 (all EEJs for inclusion 1=upstream), I2 (downstream) and E (exclusion)
	    $I1+=sprintf("%.2f",$cle*$read_count{$event}{$eej}/$eff{$event}{$eej}) if $exons eq "C1A";
	    $I2+=sprintf("%.2f",$cle*$read_count{$event}{$eej}/$eff{$event}{$eej}) if $exons eq "AC2";
	    $E+=sprintf("%.2f",$cle*$read_count{$event}{$eej}/$eff{$event}{$eej}) if $exons eq "C1C2";
	    # raw read counts for the same three sets of EEJs
	    $rI1+=$read_count{$event}{$eej} if $exons eq "C1A";
	    $rI2+=$read_count{$event}{$eej} if $exons eq "AC2";
	    $rE+=$read_count{$event}{$eej} if $exons eq "C1C2";
	    # checks if there are mappable positions for at least one EEJ for each set.
	    $eI1=1 if $exons eq "C1A";
	    $eI2=1 if $exons eq "AC2";
	    $eE=1 if $exons eq "C1C2";
	}
    }

    $check=$eI1+$eI2+$eE;
    if ($check==3){ #This requires mappability for at least one representative of each of the three junctions.
	$sum_inclusion=$I1+$I2;
	$rE+=0;
	$rI1+=0;
	$rI2+=0;
	$PSI=sprintf("%.2f",100*$sum_inclusion/((2*$E)+$sum_inclusion)) if ((2*$E)+$sum_inclusion)>0;
	$PSI="NA" if ((2*$E)+$sum_inclusion)==0;
	$all_reads_event=$rE+$rI1+$rI2+0;

	print O "$pre_data{$event}\t$PSI\t$rE\t$rI1\t$rI2\t$all_reads_event\t.\t$COMPLEX{$event}\t$E\t$I1\t$I2\t.\t.\t.\t$NAME{$event}\n";
    }
}
