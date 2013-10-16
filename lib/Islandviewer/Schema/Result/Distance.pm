use utf8;
package Islandviewer::Schema::Result::Distance;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Islandviewer::Schema::Result::Distance

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<Distance>

=cut

__PACKAGE__->table("Distance");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 rep_accnum1

  data_type: 'varchar'
  is_nullable: 0
  size: 15

=head2 rep_accnum2

  data_type: 'varchar'
  is_nullable: 0
  size: 15

=head2 distance

  data_type: 'double precision'
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "rep_accnum1",
  { data_type => "varchar", is_nullable => 0, size => 15 },
  "rep_accnum2",
  { data_type => "varchar", is_nullable => 0, size => 15 },
  "distance",
  { data_type => "double precision", is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");


# Created by DBIx::Class::Schema::Loader v0.07036 @ 2013-10-16 11:31:17
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:kkyZsMOzLkhapiDYudDNBg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
