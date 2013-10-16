use utf8;
package Islandviewer::Schema::Result::GianalysisTask;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Islandviewer::Schema::Result::GianalysisTask

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<GIAnalysisTask>

=cut

__PACKAGE__->table("GIAnalysisTask");

=head1 ACCESSORS

=head2 taskid

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 aid_id

  data_type: 'integer'
  is_nullable: 0

=head2 prediction_method

  data_type: 'varchar'
  is_nullable: 0
  size: 15

=head2 status

  data_type: 'integer'
  is_nullable: 0

=head2 parameters

  data_type: 'varchar'
  is_nullable: 0
  size: 15

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
  "taskid",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "aid_id",
  { data_type => "integer", is_nullable => 0 },
  "prediction_method",
  { data_type => "varchar", is_nullable => 0, size => 15 },
  "status",
  { data_type => "integer", is_nullable => 0 },
  "parameters",
  { data_type => "varchar", is_nullable => 0, size => 15 },
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

=item * L</taskid>

=back

=cut

__PACKAGE__->set_primary_key("taskid");


# Created by DBIx::Class::Schema::Loader v0.07036 @ 2013-10-16 11:31:17
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:Tw1+UlXE9P00kFAHij+BXg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
