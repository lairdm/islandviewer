package Islandviewer::Islandpick::BaseClass;

# Just reusing Morgan's base class paradigm to make life easier

#perldoc My_Basic_Class - for more information (or see end of this file)

use strict;
use warnings;
use Carp;

our $AUTOLOAD;

my @GENERAL_FIELDS = qw(comment);


sub new {
	my ( $class, %arg ) = @_;

	#Bless an anonymous empty hash
	my $self = bless {}, $class;

	#Fill all of the keys with the fields
	foreach (@GENERAL_FIELDS) {
		$self->{$_} = undef;
	}

	#Set each attribute that is given as an arguement
	foreach ( keys(%arg) ) {
		$self->$_( $arg{$_} );
	}
	
	return $self;
}

sub is_property{
    my ($self, $property) = @_;
    if(exists($self->{$property})){
        return 1;
    }else{
        return 0;
    }
    
}

#returns an array of all field names for this class
sub all_fields{
  my ($self) = @_;
  return keys(%$self);
}

#set all the fields in the object when given a hash
sub set_hash{
	my($self,%hash)=@_;
	foreach(keys(%hash)){
		$self->$_($hash{$_});
	}
}

#returns a hash of the complete object
sub get_hash{
	my ($self) = @_;
	return %{$self};
}

#print object to tab-delimited file
sub print_obj{
	my ($self, $filename) =@_;
	my @print_line = join('\t',values(%$self));
	if(defined($filename)){
	    open(my $OUT, '>',$filename) || croak "Can't open file: $filename for writing: $!"; 
	   print $OUT @print_line;
	}else{
	    print @print_line;
	}
	
}


# This takes the place of methods to set or get the value of an attribute
sub AUTOLOAD {
    my ($self,$newvalue) = @_;
    #get the unknown method call
    my $attr = $AUTOLOAD;

    #Keep only the method name
    $attr =~ s/.*:://;    

    #Die if the key does not already exist in the hash
    unless (exists($self->{$attr})){
	croak "No such attribute '$attr' exists in the class ";
    }

    # Turn off strict references to enable "magic" AUTOLOAD speedup
    no strict 'refs';

    # define subroutine
    *{$AUTOLOAD} = sub {my($self,$newvalue)=@_;
			$self->{$attr}=$newvalue if defined($newvalue);
			return $self->{$attr}};    

    # Turn strict references back on
    use strict 'refs';

    #Set the new value for the attribute if available
    $self->{$attr} = $newvalue if defined($newvalue);

    #Always return the current value for the attribute
    return $self->{$attr};
}

#Anything put in this method will be run when the object is destroyed
sub DESTROY{
    my ($self) = @_;
    if($self->is_property('tmp_files')){
        my $tmp_files = $self->tmp_files();
        unlink @$tmp_files or carp "Couldn't remove tmp files: @$tmp_files $!";
    }
}


1;

__END__

=head1 NAME

=head1 Synopsis

=head1 AUTHOR

Morgan Langille

=head1 Date Created

March, 2008

=cut


