package Cpanel::SysPkgs::APT::Preferences;

# cpanel - Cpanel/SysPkgs/APT/Preferences.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::LoadFile         ();
use Cpanel::FileUtils::Write ();

=head1 NAME

Cpanel::SysPkgs::APT::Preferences

=head1 DESCRIPTION

Abstract class to manage files in /etc/apt/preferences.d
for debian based distribution

=head1 SYNOPSIS

    package Cpanel::SysPkgs::APT::Preferences::XYZ;

    use parent q[Cpanel::SysPkgs::APT::Preferences];

    sub name { 'mycustomfile' }

=cut

=head1 METHODS

=head2 DIR

Main directory where the apt preferences are stored.

=cut

sub DIR {
    return q[/etc/apt/preferences.d];
}

=head2 new()

Create the object.

=cut

sub new ($pkg) {
    return bless {}, $pkg;
}

=head2 $self->name()

Needs to be define by subclasses.
Provide the name of the preferences we are going to edit.

=cut

sub name ($self) {
    die q[name is not provided by ] . ref($self);
}

=head2 $self->content()

Parse the file and returns its content as a HashRef
An empty file returns {}

=cut

sub content ($self) {

    # idea: cache the content
    return $self->{content} //= $self->_parse;

}

=head2 $self->write()

Write the previously parsed/updated content/

=cut

sub write ($self) {

    my $content = $self->content;

    my $str = '';

    foreach my $k ( sort keys $content->%* ) {
        $str .= "Package: $k\n";
        my $entry = $content->{$k};
        foreach my $attr ( sort keys $entry->%* ) {
            next if $attr eq 'Package';
            $str .= "$attr: " . $entry->{$attr} . "\n";
        }
        $str .= "\n";
    }

    chomp $str;

    Cpanel::FileUtils::Write::overwrite( $self->_filename, $str );

    $self->{content} = undef;    # force a reload next time

    return 1;
}

=head2 $self->_parse()

Parse the content of a preference file.

=cut

sub _parse ($self) {

    my @lines = split( qr/\n/, Cpanel::LoadFile::load_if_exists( $self->_filename ) // '' );

    my $data = {};

    my $entry;

    foreach my $line (@lines) {

        if ( $line =~ m{^\s*$}a ) {
            if ( ref $entry ) {
                die q[Missing Package entry] unless defined $entry->{Package};
                $data->{ $entry->{Package} } = $entry;
                $entry = undef;
            }
            next;
        }

        if ( $line =~ m{^\s*(.+):\s*(.+)\s*$}a ) {
            my ( $k, $v ) = ( $1, $2 );
            $entry //= {};
            $entry->{$k} = $v;
        }
    }

    if ( ref $entry ) {
        die q[Missing Package entry] unless defined $entry->{Package};
        $data->{ $entry->{Package} } = $entry;
    }

    return $data;
}

=head2 $self->_filename()

filename of the preference file

=cut

sub _filename ($self) {
    return $self->{_filename} //= DIR . '/' . $self->name;
}

1;
