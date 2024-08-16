package Cpanel::ZoneFile::Versioning;

# cpanel - Cpanel/ZoneFile/Versioning.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::ZoneFile::Versioning

=head1 SYNOPSIS

    my $new_line = Cpanel::ZoneFile::Versioning::version_line($old_line);

=head1 DESCRIPTION

cPanel stores a bit of metadata in the form of a first-line comment in
all DNS zone files. This module interfaces with that metadata when it’s time
to update the zone file.

=cut

#----------------------------------------------------------------------

use Cpanel::Hostname ();
use Cpanel::Version  ();

our $VERSION = 1.3;

our $STARTMATCH = qr/^;\s*cPanel\s*(\S+)/;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $new_line = version_line( [ $OLDSTUFF [, $UPDATE_TIME [, $HOSTNAME ] ] ] )

Returns a new version line without a trailing newline.

$OLDSTUFF is one of:

=over

=item * The old version line.

=item * The match from this module’s C<$STARTMATCH> global.
(NB: That’s “start”, not “smart”. :-P)

=item * Nothing/falsy, in which case the current cPanel & WHM version is
used.

=back

$UPDATE_TIME and $HOSTNAME will be filled in automatically if not given.

=cut

sub version_line {
    my ( $current_line, $update_time, $hostname ) = @_;

    my %version_data;

    if ( $current_line =~ /^first:(\d.*)/ && $current_line !~ s/\s// ) {
        $version_data{'first'} = $1;
    }
    elsif ( $current_line =~ /^\s*;\s*cPanel\s*([.0-9]+)\s*$/ ) {
        $version_data{$1} = 1;
    }
    elsif ( $current_line =~ s/^\s*;\s*cPanel\s*// ) {
        %version_data = map { ( split( /:/, $_, 2 ) )[ 0, 1 ] } split( /\s+/, $current_line );
        delete $version_data{'Cpanel'};
    }

    $version_data{'latest'} = Cpanel::Version::get_version_display() || 'unknown';
    $version_data{'first'} ||= $version_data{'latest'};
    $version_data{'Cpanel::ZoneFile::VERSION'} = $VERSION;
    $version_data{'(update_time)'}             = $update_time || _get_time();                       # () added for quicker regex find
                                                                                                    # we cannot use mtime because it was not always updated
                                                                                                    # in prior cPanel versions which can lead to bad behavior
                                                                                                    # when dnsadmin figures out which is the newest zone
    $version_data{'hostname'}                  = $hostname    || Cpanel::Hostname::gethostname();
    return '; cPanel ' . join( ' ', map { "$_:$version_data{$_}" } sort { ( $b eq 'first' ) <=> ( $a eq "first" ) || ( $a cmp $b ) } keys %version_data );
}

#for testing
sub _get_time { return time }

1;
