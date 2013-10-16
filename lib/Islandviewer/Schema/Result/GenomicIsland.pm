use utf8;
package Islandviewer::Schema::Result::GenomicIsland;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Islandviewer::Schema::Result::GenomicIsland

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<GenomicIsland>

=cut

__PACKAGE__->table("GenomicIsland");

=head1 ACCESSORS

=head2 gi

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 aid_id

  data_type: 'integer'
  is_nullable: 0

=head2 start

  data_type: 'integer'
  is_nullable: 0

=head2 end

  data_type: 'integer'
  is_nullable: 0

=head2 prediction_method

  data_type: 'varchar'
  is_nullable: 0
  size: 15

=cut

__PACKAGE__->add_columns(
  "gi",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "aid_id",
  { data_type => "integer", is_nullable => 0 },
  "start",
  { data_type => "integer", is_nullable => 0 },
  "end",
  { data_type => "integer", is_nullable => 0 },
  "prediction_method",
  { data_type => "varchar", is_nullable => 0, size => 15 },
);

=head1 PRIMARY KEY

=over 4

=item * L</gi>

=back

=cut

__PACKAGE__->set_primary_key("gi");


# Created by DBIx::Class::Schema::Loader v0.07036 @ 2013-10-16 11:31:17
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:aLJTdC0OzzNRfrVrRzG6lw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
