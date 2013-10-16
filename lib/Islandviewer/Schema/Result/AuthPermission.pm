use utf8;
package Islandviewer::Schema::Result::AuthPermission;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Islandviewer::Schema::Result::AuthPermission

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<auth_permission>

=cut

__PACKAGE__->table("auth_permission");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 name

  data_type: 'varchar'
  is_nullable: 0
  size: 50

=head2 content_type_id

  data_type: 'integer'
  is_nullable: 0

=head2 codename

  data_type: 'varchar'
  is_nullable: 0
  size: 100

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "name",
  { data_type => "varchar", is_nullable => 0, size => 50 },
  "content_type_id",
  { data_type => "integer", is_nullable => 0 },
  "codename",
  { data_type => "varchar", is_nullable => 0, size => 100 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 UNIQUE CONSTRAINTS

=head2 C<content_type_id>

=over 4

=item * L</content_type_id>

=item * L</codename>

=back

=cut

__PACKAGE__->add_unique_constraint("content_type_id", ["content_type_id", "codename"]);


# Created by DBIx::Class::Schema::Loader v0.07036 @ 2013-10-16 11:31:17
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:scebo9tNkHLYx32saz8cPw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
