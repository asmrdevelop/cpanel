package Cpanel::User::Tags;

# cpanel - Cpanel/User/Tags.pm                     Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use SQL::Abstract::Complete ();

use parent qw{ Cpanel::SQLite::UserData };

use constant FILENAME => q[tags.sqlite];

=encoding utf8

=head1 NAME

Cpanel::User::Tags

=head1 SYNOPSIS

    use Cpanel::User::Tags ();

    my $tags = Cpanel::User::Tags->new();              # use ~/.cpanel/tags.sqlite file

    # alternatively you can set your own file location
    $tags = Cpanel::User::Tags->new( filename => q[store/mytags.sqlite] ); # use ~/.cpanel/store/mytags.sqlite

    # add a single tag to one element identified by its UniqueId
    $tags->add_tag_to_element( 'mytag', 'myelementUID' );

    # add multiple tags
    $tags->add_tags_to_element( [ qw{ a list of tags } ] , 'myelementUID' );

    my $list_of_tags = $tags->get_tags_for( 'myelementUID' );
    # @$list_of_tags = [ qw{ a list of tags } ]

    $tags->remove_tag_from_element ( 'mytag' => 'myelementUID' );
    $tags->remove_tags_from_element( [ qw{ some tags } ] => 'myelementUID' );

    $tags->rename_tag( 'mytag' => 'updatedName' );


=head1 DESCRIPTION

This is used to store some key / value entries in one SQLite database located in the user home directory.

=head1 FUNCTIONS

=head2 $self->add_tag_to_element( $tag, $element_to_tag )

Add a tag to an element identified by its UniqueID

    $tags->add_tag_to_element( 'mytag', 'myelementUID' );

=cut

sub add_tag_to_element ( $self, $tag, $element_to_tag ) {
    return $self->add_tags_to_element( [$tag], $element_to_tag );
}

=head2 $self->add_tags_to_element( $tags, $element_to_tag )

Add multiple tags to an element identified by its UniqueID

    $tags->add_tags_to_element( [ qw{ a list of tags } ] , 'myelementUID' );

=cut

sub add_tags_to_element ( $self, $tags, $element_to_tag ) {

    return unless ref $tags && scalar @$tags;

    my $elt_id = $self->_select_or_insert_element_by_name($element_to_tag) or return;

    my $failures = 0;
    my $last_error;

    foreach my $tag (@$tags) {
        my $tag_id = $self->_select_or_insert_tag_by_name($tag) or next;

        my $results = eval { $self->db->insert( 'elt_tags', { element_id => $elt_id, tag_id => $tag_id } ) };
        if ($@) {
            $last_error = $@;
            if ( $last_error =~ qr{UNIQUE constraint failed} ) {
                next;
            }
            ++$failures;
            next;
        }

        $failures++ unless $results;
    }
    _massage_and_throw_error($last_error) if $failures && $last_error;

    return $failures ? 0 : 1;
}

=head2 $self->get_tags_for( $element_uid )

Retrieve the list of tags for an element identified by its UniqueID.

    map { say "Element is tagged with: ", $_ } $tags->get_tags_for( 'myelementUID' )->@*;

=cut

sub get_tags_for ( $self, $id ) {

    my $sac = SQL::Abstract::Complete->new;

    # sqlite> select t.name
    # from tags t
    # join elt_tags et on t.id=et.tag_id
    # join elements e on e.id=et.element_id
    # where e.name='theme:slug';
    # mytag

    # SQL::Abstract::Complete
    my ( $sql, @bind ) = $sac->select(

        # tables
        [
            [ [qw{ tags t}] ],
            [
                \q{ JOIN },
                { 'elt_tags' => 'et' },
                \q{ ON t.id = et.tag_id },
            ],
            [
                \q{ JOIN },
                { 'elements' => 'e' },
                \q{ ON e.id = et.element_id },
            ],
        ],

        # what
        ['t.name'],

        # where
        { 'e.name' => $id },

        # other
        { 'order_by' => 't.name' }
    );

    my $r    = $self->db->query( $sql, @bind );
    my $tags = $r->arrays->reduce( sub { push @$a, $b->[0]; $a }, [] );

    return $tags;
}

=head2 $self->rename_tag( $current_name, $updated_name  )

Rename the tag identified by the name '$current_name' to a new name '$updated_'

=cut

sub rename_tag ( $self, $current_name, $updated_name ) {
    return $self->db->update( 'tags', { name => $updated_name }, { name => $current_name } );
}

=head2 $self->remove_tag_from_element ( $tag, $element )

Remove one tag from one element identified by the UniqueID '$element'.

    $tags->remove_tag_from_element ( 'mytag' => 'myelementUID' );

=cut

sub remove_tag_from_element ( $self, $tag, $element ) {
    return $self->remove_tags_from_element( [$tag], $element );
}

=head2 $self->remove_tags_from_element ( $tags, $element )

Remove multiple tags from one element identified by the UniqueID '$element'.

    $tags->remove_tags_from_element( [ qw{ some tags } ] => 'myelementUID' );

=cut

sub remove_tags_from_element ( $self, $tags, $element ) {

    return unless ref $tags && scalar @$tags;

    my $element_id = eval { $self->db->select( 'elements', ['id'], { name => $element } )->hash->{id} } or return;

    my $ok = 1;
    foreach my $tag (@$tags) {
        my $tag_id = eval { $self->db->select( 'tags', ['id'], { name => $tag } )->hash->{id} }
          or next;
        $ok = 0 unless $self->db->delete( 'elt_tags', { element_id => $element_id, tag_id => $tag_id } );
    }

    return $ok;
}

sub _massage_and_throw_error ($txt) {
    return unless length $txt;
    my ($firstline) = split( "\n", $txt );
    $firstline =~ s{\s+at\s+/usr.*$}{}m;

    $firstline =~ s{^.+?\sfailed:\s}{};
    $firstline =~ s{^DBD::\S+}{};

    die "$firstline\n";
}

sub _select_or_insert_element_by_name ( $self, $name ) {
    return $self->_select_or_insert( 'elements', name => $name );
}

sub _select_or_insert_tag_by_name ( $self, $name ) {
    return $self->_select_or_insert( 'tags', name => $name );
}

1;

__DATA__

@@ migrations

-- 1 up

create table elements (
    id   INTEGER PRIMARY KEY,
    name TEXT NOT NULL UNIQUE
);

create table tags (
    id    INTEGER PRIMARY KEY,
    name TEXT NOT NULL UNIQUE
);

create table elt_tags (
    element_id INTEGER,
    tag_id     INTEGER,

    PRIMARY KEY (element_id, tag_id),

    FOREIGN KEY (element_id)
      REFERENCES elements (id)
         ON DELETE CASCADE
         ON UPDATE NO ACTION,

    FOREIGN KEY (tag_id)
      REFERENCES tags (id)
         ON DELETE CASCADE
         ON UPDATE NO ACTION
);

-- 1 down

drop table elements;
drop table tags;
drop table elt_tags;
