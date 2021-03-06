#!/usr/bin/env perl

use strict;

my $previous_read;
my $hitB;
my %tally;
my %POS;
my %EJ;

while (<STDIN>){
    my $read="";
    my @t=split(/\t/);
    
    ($read)=$t[0]=~/(.+)\-/;
    $read=$t[0] if !$read;
    
    my $hit=$t[2];
    
    if ($read ne $previous_read){
        $tally{$hit}++;
	$EJ{$hit}++;
        $POS{$hit}{$t[3]}++;
    }
    $previous_read=$read;
    $hitB=$hit;
}

foreach my $hit (sort (keys %tally)){
    my $p_p="";
    foreach my $pos (sort {$a<=>$b} (keys %{$POS{$hit}})){
	$p_p.="$pos:$POS{$hit}{$pos},";
    }
    chop($p_p);

    print STDOUT "$hit\t$tally{$hit}\t$p_p\n";
}
