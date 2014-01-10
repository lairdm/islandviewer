=head1 NAME

    Islandviewer::IslandFetcher

=head1 DESCRIPTION

    Object to barse the genbank file and fetch all the
    records within a given set of islands

=head1 SYNOPSIS

    use Islandviewer::IslandFetcher;

    $vir_obj = Islandviewer::IslandFetcher->new({islands => $island_array_obj);

=head1 AUTHOR

    Matthew Laird
    Brinkman Laboratory
    Simon Fraser University
    Email: lairdm@sfu.ca

=head1 LAST MAINTAINED

    Dec 12, 2013

=cut

package Islandviewer::IslandFetcher;

use strict;
use Moose;
use Log::Log4perl qw(get_logger :nowarn);
use File::Temp qw/ :mktemp /;
use Data::Dumper;
use List::Util qw[min max];

use Bio::SeqIO;
use Bio::Seq;

my $cfg; my $logger;

sub BUILD {
    my $self = shift;
    my $args = shift;

    $cfg = Islandviewer::Config->config;

    $logger = Log::Log4perl->get_logger;

    $self->{islands} = $args->{islands};

}

sub fetchGenes {
    my $self = shift;
    my $genbank_file = shift;

    # Sanity check, the file exists, right?
    unless( -e $genbank_file ) {
	$logger->logdie("Error, genbank file $genbank_file doesn't seem to exist");
    }

    # Let's open the file and parse it
    my $seqio_obj = Bio::SeqIO->new(-file => $genbank_file);

    my @genes;

    # We have to iterate because draft genomes could have multiple
    # sequences in them
    while(my $seq_obj = $seqio_obj->next_seq) {
	for my $feature_obj ($seq_obj->get_SeqFeatures) {
	    if($feature_obj->primary_tag eq 'CDS') {
		if($feature_obj->has_tag('protein_id')) {
		    my $gene = undef; my @product = (); my @locus = ();
		    if($feature_obj->has_tag('gene')) {
			$gene = join '; ', $feature_obj->get_tag_values('gene');
		    }
		    if($feature_obj->has_tag('product')) {
			for my $v ($feature_obj->get_tag_values('product')) {
			    push @product, $v;
			}
		    }
		    if($feature_obj->has_tag('locus_tag')) {
			for my $v ($feature_obj->get_tag_values('locus_tag')) {
			    push @locus, $v;
			}
		    }

#		    if(my $gis = $self->rangeinislands($feature_obj->location->start,
#					     $feature_obj->location->end)) {
		    my $gis = $self->rangeinislands($feature_obj->location->start,
						    $feature_obj->location->end);

		    # Ensure $gis is an array since we sometimes
		    # get a scalar if only one is returned
		    if(ref($gis) eq "SCALAR") {
			$gis = [$gis];
		    }

		    $logger->trace("For " . $feature_obj->get_tag_values('protein_id') . " found gis " . @{$gis});

		    push @genes, [$feature_obj->location->start, 
				  $feature_obj->location->end,
				  $feature_obj->get_tag_values('protein_id'),
				  $gis, 
				  $feature_obj->strand,
				  $gene,
				  join(',', @product),
				  join(',', @locus)
		    ];
#		    } else {
			# Blast! First time I wrote this I thought we only
			# wanted genes in islands, but we actually need
			# all of them... mark genes not in islands with 0
			# for the GI number
#			push @genes, [$feature_obj->location->start, 
#				      $feature_obj->location->end,
#				      $feature_obj->get_tag_values('protein_id'),
#				      0,
#				      $feature_obj->strand,
#				      $gene,
#				      join(',', @product),
#				      join(',', @locus)
#			];
#		    }
		    my @ary = $genes[-1];
		print Dumper @ary;
		}
	    }
	}
    }

    return \@genes;
}

sub rangeinislands {
    my $self = shift;
    my $start = shift;
    my $end = shift;

    my @gis = ();

    for my $island (@{$self->{islands}}) {
	my $overlap = max(0, (min($end, $island->[2]) - max($start, $island->[1])));
	if($overlap > 0) {
	    push @gis, $island->[0];
	}
    }
	
#	if(($start >= $island->[1]) &&
#	   ($end <= $island->[2])) {
#	    return  $island->[0];
#	}
#    }

    return \@gis;
}

1;
