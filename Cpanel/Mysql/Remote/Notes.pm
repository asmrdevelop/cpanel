package Cpanel::Mysql::Remote::Notes;

# cpanel - Cpanel/Mysql/Remote/Notes.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::Mysql::Remote::Notes

=head1 SYNOPSIS

    use Cpanel::Mysql::Remote::Notes ();
    my $notes = Cpanel::Mysql::Remote::Notes(username => $cpuser_name);
    $notes->set(
        'foo.example.com' => 'foo is a MySQL server',
        '127.0.0.1'       => 'this is localhost',
    );

    my %notes = $notes_obj->get_all;

    my $foo_note = $notes_obj->delete('foo.example.com');

=head1 DESCRIPTION

This is a simple class for persisting a hash of name-value pairs into a
JSON file, for the purposes of storing comments or notes about a user's
remote MySQL servers. The JSON file is stored in
F</var/cpanel/mysql/notes/{username}.json>, and will be automatically
deleted if the last entry is deleted from the corresponding notes
object.

=cut

use strict;
use warnings;
use Cpanel::Autodie                 ();
use Cpanel::Exception               ();
use Cpanel::SafeDir::MK             ();
use Cpanel::Transaction::File::JSON ();

=head1 PACKAGE VARIABLES

=head2 $NOTES_DIR

Directory for storing Remote MySQL notes. Defaults to
F</var/cpanel/mysql/notes>.

=cut

our $NOTES_DIR = '/var/cpanel/mysql/notes';

=head1 METHODS

=head2 new(username => $cpuser_name)

Constructor class method that takes a single argument, named
I<username>, which is expected to contain the cPanel username used to
store the notes information.

=cut

sub new {
    my ( $class, @args ) = @_;
    my %args = ref $args[0] eq 'HASH' ? %{ $args[0] } : @args;
    my $self = bless {}, $class;

    $self->{username} = $args{username}
      or die Cpanel::Exception::create(
        'MissingParameter', [ name => 'username' ],
      );
    $self->{filename} = "$NOTES_DIR/$self->{username}.json";
    Cpanel::SafeDir::MK::safemkdir( $NOTES_DIR, '0700' );

    return $self;
}

=head2 get_all

Retrieves all contents of the JSON file as a hash.

=cut

sub get_all {
    my $self = shift;

    my $txn = Cpanel::Transaction::File::JSON->new(
        path => $self->{filename},
    );
    my $notes_ref = $txn->get_data;

    return %{$notes_ref} if ref $notes_ref eq 'HASH';
    return;
}

=head2 set(%notes)

Takes a hash of host name keys and note values and adds/updates them
in the JSON file. Server names are truncated to 60 characters (same
as in the MySQL C<users> table) and notes are truncated to 255
characters.

=cut

sub set {
    my ( $self, %arg_notes ) = @_;
    my %new_notes;    # trim keys to 60 chars and values to 255 chars
    for ( keys %arg_notes ) {
        $new_notes{ substr $_, 0, 60 } = substr $arg_notes{$_}, 0, 255;
    }

    my $txn = Cpanel::Transaction::File::JSON->new(
        path => $self->{filename},
    );
    my $notes_ref = $txn->get_data;
    my %notes;
    if ( ref $notes_ref eq 'HASH' ) { %notes = %{$notes_ref} }
    %notes = ( %notes, %new_notes );
    $txn->set_data( \%notes );
    $txn->save_and_close_or_die;

    return;
}

=head2 delete($server)

Acts much like the Perl L<perlfunc/delete> function, deleting an
element from the JSON file. It even returns the value deleted.

=cut

sub delete {
    my ( $self, $host ) = @_;

    my $txn = Cpanel::Transaction::File::JSON->new(
        path => $self->{filename},
    );
    my $notes_ref = $txn->get_data;
    my $value     = delete $notes_ref->{$host}
      if ref $notes_ref eq 'HASH';

    if ( ref $notes_ref eq 'HASH' and keys %{$notes_ref} ) {
        $txn->set_data($notes_ref);
        $txn->save_and_close_or_die;
    }
    else {
        $txn->close_or_die;
        Cpanel::Autodie::unlink_if_exists( $self->{filename} );
    }

    return $value;
}

=head2 delete_all

Deletes the notes JSON file entirely.

=cut

sub delete_all {
    my $self = shift;
    return Cpanel::Autodie::unlink_if_exists( $self->{filename} );
}

1;
