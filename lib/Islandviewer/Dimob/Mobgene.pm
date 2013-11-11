=head1 NAME

    Islandviewer::Dimob::Mobgene

=head1 DESCRIPTION

    A repackaging of Will's original Dimob software

=head1 SYNOPSIS

    use Islandviewer::Dimob::Mobgene;

    $mobgene_obj = Islandviewer::Dimob::Mobgene->new();

    $mobgene_obj->parse_hmmer($hmmer_file, $parse_evaluecutoff);
    $mobgene_obj->parse_ptt($ptt_file);

=head1 AUTHOR

    Matthew Laird
    Brinkman Laboratory
    Simon Fraser University
    Email: lairdm@sfu.ca

=head1 LAST MAINTAINED

    Nov 10, 2013

=cut

package Islandviewer::Dimob::Mobgene;

use strict;
use Moose;
use Log::Log4perl qw(get_logger :nowarn);

use Bio::SearchIO;

use Islandviewer::Dimob::tabdelimitedfiles;

my $cfg; my $logger; my $cfg_file;

sub BUILD {
    my $self = shift;
    my $args = shift;

    $cfg = Islandviewer::Config->config;

    $logger = Log::Log4perl->get_logger;

}

#given a hmmer output file, parse it and return a list of mobility genes
#returns a {pid}{domain_name}{E_value} hash structure

sub parse_hmmer {
    my $self = shift;
    	my $hmmer_file         = shift;
	my $parse_evaluecutoff = shift;

	my %domain_hash;
	my %mobgenes;
	open( HMMINPUT, $hmmer_file );

	#making sure that the file is present and not empty
	if ( -s "$hmmer_file" ) {
		#print "parse_hmmer: parsing HMMER results...\n";
		my $in =
		  Bio::SearchIO->new( -file => "$hmmer_file", -format => 'hmmer' );
		while ( my $res = $in->next_result ) {
			my %domains_evalues;
			while ( my $hit = $res->next_hit ) {
				if ( $hit->significance <= $parse_evaluecutoff ) {
					$domains_evalues{ $hit->name } = $hit->significance;
				}
			}
			if ( ( scalar( keys %domains_evalues ) ) > 0 ) {
				my $id;
				if ($res->query_name=~/gi\|(\d+)\|/){
					$id = $1;
				}
				else{
					$id = $res->query_name;
				}
				$mobgenes{ $id } = {%domains_evalues};
			}
		}
	}
	return \%mobgenes;
}

#given a ptt file and extract a list of genes (GI number and accession) that
sub parse_ptt {
    my $self = shift;
    #are annotated as mobility genes
    my $ptt_file    = shift;
    my $header_line = 3;       #currently the 3rd line of ptt file is the header
    my %mobgenes;
    my ( $header_arrayref, $pttfh ) =
	extract_headerandbodyfh( $ptt_file, $header_line );
    my $ptt_table_hashref = table2hash_rowfirst( $header_arrayref, 4, $pttfh );
    #print "here's the dumping\n";
    #print Dumper $ptt_table_hashref;
    foreach my $pid (keys %{$ptt_table_hashref} ) {
	my $product = $ptt_table_hashref->{$pid}->{'Product'};
	if (   $product =~ /transposase/i
	       || $product =~ /IstB-like/
	       || $product =~ /insertion element 1/i
	       || $product =~ /recombinase/i )
	{
	    $mobgenes{$pid} = $product;
	}
    }
    return \%mobgenes;

}

1;
