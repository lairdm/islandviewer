# AUTH: Anastasia A.  Fedynak
# DATE: 08 April, 2004
# DESC: Blast_hit class stores information on a single blast hit. 
#	Blast_hit can be used in conjunction with BioPerl
#	StandAloneBlastObject to store each Hsp object.
# FILE: Blast_hit.pm

package Islandviewer::Islandpick::BlastHit;
use Carp;

my %attributes = (
	start	=> undef,	# start position of blast hit
	end  	=> undef,	# end position of blast hit
	length	=> undef,	# length of blast hit
	score	=> undef,	# score of blast hit
	frac_id	=> undef,	# fraction identity of blast hit
	name	=> undef,	# name of organism hit originated from
);


# new():
# ARGS: None
# RETU: Memory allocated for a new Blast_hit object
# DESC: Creates a new Blast_hit object with undefined attributes.
sub new {
	my $self = {
		%attributes,
	};
	bless $self;
	return $self;
}


# AUTOLOAD():
# ARGS: Blast_hit object
# RETU: None
# DESC: Assignes argument value to attribute if argument defined,
#	returns attribute value if argument undefined.
sub AUTOLOAD {
	my $self = shift;
	my $field = $AUTOLOAD;
	$field =~ s/.*://;
	unless (exists $self->{$field}) {
		croak "Can't access '$field' field\n";
	}
	if (@_) {
		return $self->{$field} = shift;
	}
	else {
		return $self->{$field};
	}
}

# toString():
# ARGS: Blast_hit object
# RETU: String representation of Blast_hit object
# DESC: Creates and returns string representation of Blast_hit object
sub toString {
	my $self = shift;
	return  "srt: " . $self->start . 
		" end: " . $self->end .
	        " len: " . $self->length . 
		" sco: " . $self->score .
	        " fid: " . $self->frac_id .
	        " name: " . $self->name .
		"\n"; 
}

1;
