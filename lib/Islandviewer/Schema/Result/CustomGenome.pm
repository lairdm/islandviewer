use utf8;
package Islandviewer::Schema::Result::CustomGenome;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Islandviewer::Schema::Result::CustomGenome

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<CustomGenome>

=cut

__PACKAGE__->table("CustomGenome");

=head1 ACCESSORS

=head2 cid

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 name

  data_type: 'varchar'
  is_nullable: 0
  size: 60

=head2 cds_num

  data_type: 'integer'
  is_nullable: 0

=head2 rep_size

  data_type: 'integer'
  is_nullable: 0

=head2 filename

  data_type: 'varchar'
  is_nullable: 1
  size: 60

=head2 submit_date

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "cid",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "name",
  { data_type => "varchar", is_nullable => 0, size => 60 },
  "cds_num",
  { data_type => "integer", is_nullable => 0 },
  "rep_size",
  { data_type => "integer", is_nullable => 0 },
  "filename",
  { data_type => "varchar", is_nullable => 1, size => 60 },
  "submit_date",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    is_nullable => 0,
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</cid>

=back

=cut

__PACKAGE__->set_primary_key("cid");


# Created by DBIx::Class::Schema::Loader v0.07036 @ 2013-10-16 11:31:17
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:VZ7n1TtWntQXzR8kc2eggg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
