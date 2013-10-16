use utf8;
package Islandviewer::Schema::Result::Analysis;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Islandviewer::Schema::Result::Analysis

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<Analysis>

=cut

__PACKAGE__->table("Analysis");

=head1 ACCESSORS

=head2 aid

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 atype

  data_type: 'integer'
  is_nullable: 0

=head2 ext_id

  data_type: 'varchar'
  is_nullable: 0
  size: 10

=head2 default_analysis

  data_type: 'tinyint'
  is_nullable: 0

=head2 status

  data_type: 'integer'
  is_nullable: 0

=head2 start_date

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  is_nullable: 0

=head2 complete_date

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "aid",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "atype",
  { data_type => "integer", is_nullable => 0 },
  "ext_id",
  { data_type => "varchar", is_nullable => 0, size => 10 },
  "default_analysis",
  { data_type => "tinyint", is_nullable => 0 },
  "status",
  { data_type => "integer", is_nullable => 0 },
  "start_date",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    is_nullable => 0,
  },
  "complete_date",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    is_nullable => 0,
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</aid>

=back

=cut

__PACKAGE__->set_primary_key("aid");


# Created by DBIx::Class::Schema::Loader v0.07036 @ 2013-10-16 11:31:17
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:lg2UlMlOlpfUkMk26nCv4A


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
