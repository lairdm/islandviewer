use utf8;
package Islandviewer::Schema::Result::DjangoSession;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Islandviewer::Schema::Result::DjangoSession

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<django_session>

=cut

__PACKAGE__->table("django_session");

=head1 ACCESSORS

=head2 session_key

  data_type: 'varchar'
  is_nullable: 0
  size: 40

=head2 session_data

  data_type: 'longtext'
  is_nullable: 0

=head2 expire_date

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "session_key",
  { data_type => "varchar", is_nullable => 0, size => 40 },
  "session_data",
  { data_type => "longtext", is_nullable => 0 },
  "expire_date",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    is_nullable => 0,
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</session_key>

=back

=cut

__PACKAGE__->set_primary_key("session_key");


# Created by DBIx::Class::Schema::Loader v0.07036 @ 2013-10-16 11:31:17
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:G3QB/iIai/GVwvqxQGhqzg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
