use utf8;
package Islandviewer::Schema::Result::AuthUser;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Islandviewer::Schema::Result::AuthUser

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<auth_user>

=cut

__PACKAGE__->table("auth_user");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 password

  data_type: 'varchar'
  is_nullable: 0
  size: 128

=head2 last_login

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  is_nullable: 0

=head2 is_superuser

  data_type: 'tinyint'
  is_nullable: 0

=head2 username

  data_type: 'varchar'
  is_nullable: 0
  size: 30

=head2 first_name

  data_type: 'varchar'
  is_nullable: 0
  size: 30

=head2 last_name

  data_type: 'varchar'
  is_nullable: 0
  size: 30

=head2 email

  data_type: 'varchar'
  is_nullable: 0
  size: 75

=head2 is_staff

  data_type: 'tinyint'
  is_nullable: 0

=head2 is_active

  data_type: 'tinyint'
  is_nullable: 0

=head2 date_joined

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "password",
  { data_type => "varchar", is_nullable => 0, size => 128 },
  "last_login",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    is_nullable => 0,
  },
  "is_superuser",
  { data_type => "tinyint", is_nullable => 0 },
  "username",
  { data_type => "varchar", is_nullable => 0, size => 30 },
  "first_name",
  { data_type => "varchar", is_nullable => 0, size => 30 },
  "last_name",
  { data_type => "varchar", is_nullable => 0, size => 30 },
  "email",
  { data_type => "varchar", is_nullable => 0, size => 75 },
  "is_staff",
  { data_type => "tinyint", is_nullable => 0 },
  "is_active",
  { data_type => "tinyint", is_nullable => 0 },
  "date_joined",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    is_nullable => 0,
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 UNIQUE CONSTRAINTS

=head2 C<username>

=over 4

=item * L</username>

=back

=cut

__PACKAGE__->add_unique_constraint("username", ["username"]);


# Created by DBIx::Class::Schema::Loader v0.07036 @ 2013-10-16 11:31:17
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:GmagdqXgeZIIFzT49ByyvQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
