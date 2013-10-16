use utf8;
package Islandviewer::Schema::Result::DjangoContentType;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Islandviewer::Schema::Result::DjangoContentType

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<django_content_type>

=cut

__PACKAGE__->table("django_content_type");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 name

  data_type: 'varchar'
  is_nullable: 0
  size: 100

=head2 app_label

  data_type: 'varchar'
  is_nullable: 0
  size: 100

=head2 model

  data_type: 'varchar'
  is_nullable: 0
  size: 100

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "name",
  { data_type => "varchar", is_nullable => 0, size => 100 },
  "app_label",
  { data_type => "varchar", is_nullable => 0, size => 100 },
  "model",
  { data_type => "varchar", is_nullable => 0, size => 100 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 UNIQUE CONSTRAINTS

=head2 C<app_label>

=over 4

=item * L</app_label>

=item * L</model>

=back

=cut

__PACKAGE__->add_unique_constraint("app_label", ["app_label", "model"]);


# Created by DBIx::Class::Schema::Loader v0.07036 @ 2013-10-16 11:31:17
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:Bu1ofWOIfBb98VL/qLtihA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
