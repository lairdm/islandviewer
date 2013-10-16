use utf8;
package Islandviewer::Schema::Result::AuthUserUserPermission;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Islandviewer::Schema::Result::AuthUserUserPermission

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<auth_user_user_permissions>

=cut

__PACKAGE__->table("auth_user_user_permissions");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 user_id

  data_type: 'integer'
  is_nullable: 0

=head2 permission_id

  data_type: 'integer'
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "user_id",
  { data_type => "integer", is_nullable => 0 },
  "permission_id",
  { data_type => "integer", is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 UNIQUE CONSTRAINTS

=head2 C<user_id>

=over 4

=item * L</user_id>

=item * L</permission_id>

=back

=cut

__PACKAGE__->add_unique_constraint("user_id", ["user_id", "permission_id"]);


# Created by DBIx::Class::Schema::Loader v0.07036 @ 2013-10-16 11:31:17
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:4R5CBxmk0WbrFWKJNW7jzg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
