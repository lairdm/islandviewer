use utf8;
package Islandviewer::Schema::Result::IslandPick;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Islandviewer::Schema::Result::IslandPick

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<IslandPick>

=cut

__PACKAGE__->table("IslandPick");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 taskid_id

  data_type: 'integer'
  is_nullable: 0

=head2 reference_rep_accnum

  data_type: 'varchar'
  is_nullable: 0
  size: 100

=head2 alignment_program

  data_type: 'varchar'
  is_nullable: 0
  size: 50

=head2 min_gi_size

  data_type: 'integer'
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "taskid_id",
  { data_type => "integer", is_nullable => 0 },
  "reference_rep_accnum",
  { data_type => "varchar", is_nullable => 0, size => 100 },
  "alignment_program",
  { data_type => "varchar", is_nullable => 0, size => 50 },
  "min_gi_size",
  { data_type => "integer", is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");


# Created by DBIx::Class::Schema::Loader v0.07036 @ 2013-10-16 11:31:17
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:9Mi/JJ8XHpFPdzqsp1unJA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
