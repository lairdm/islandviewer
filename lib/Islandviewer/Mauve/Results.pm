package Islandviewer::Mauve::Results;

# We're just going to reuse Morgan's object from the
# original Islandviewer, it'll make life easier...

#Stores all the results of the Mauve alignment tool in memory.
#Basically each output file is stored in an array in the object

use strict;
use warnings;
our $AUTOLOAD;    # before Perl 5.6.0 say "use vars '$AUTOLOAD';"
use Carp;



# The constructor for the class
sub new {
    my ( $class, %arg ) = @_;
    my $self = bless {
	output            => $arg{output}             || undef,
	output_alignment  => $arg{output_alignment}   || undef,
	output_guide_tree => $arg{output_guide_tree}  || undef,
	island_output     => $arg{island_output}      || undef,
	backbone_output   => $arg{backbone_output}    || undef,
	stdout            => $arg{stdout}             || undef,
	stderr			=> $arg{stderr}	      || undef
    }, $class;

    return $self;
}

# This takes the place of such accessor definitions as:
#  sub get_attribute { ... }
# and of such mutator definitions as:
#  sub set_attribute { ... }
sub AUTOLOAD {
    my ( $self, $newvalue ) = @_;

    #get the unknown method call
    my $attr = $AUTOLOAD;

    #Keep only the method name
    $attr =~ s/.*:://;

    #Die if the key does not already exist in the hash
    unless ( exists( $self->{$attr} ) ) {
	croak "No such attribute '$attr' exists in the class ";
    }

    # Turn off strict references to enable "magic" AUTOLOAD speedup
    no strict 'refs';

    # define subroutine
    *{$AUTOLOAD} = sub {
	my ( $self, $newvalue ) = @_;
	$self->{$attr} = $newvalue if defined($newvalue);
	return $self->{$attr};
    };

    # Turn strict references back on
    use strict 'refs';

    #Set the new value for the attribute if available
    $self->{$attr} = $newvalue if defined($newvalue);

    #Always return the current value for the attribute
    return $self->{$attr};
}

sub DESTROY {

}

1;

__END__

=head1 NAME

Mauve_Results: Stores and allows access the results of a Mauve alignment

=head1 Synopsis
    #Should only be used by the Mauve class.

=head1 AUTHOR

    Morgan Langille

=head1 Date

    May 23th, 2006

=cut

