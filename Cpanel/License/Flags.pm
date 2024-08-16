package Cpanel::License::Flags;

# cpanel - Cpanel/License/Flags.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

our $cpanel_flags;
my $FLAGS_CACHE_FILE = '/var/cpanel/flagscache';

=encoding utf-8

=head1 NAME

Cpanel::License::Flags

=head1 DESCRIPTION

Helper functions related to checking for specific flags on the current product license.

=head1 SYNOPSIS

    use Cpanel::License::Flags;
    if (Cpanel::License::Flags::has_flag('dev')) {
        print "DEVELOPER LICENSE\n";
    }
    elsif(Cpanel::License::Flags::has_flag('trial')) {
        print "TRIAL LICENSE\n";
    }
    elsif(Cpanel::License::Flags::has_flag('vps')) {
        print "VPS LICENSE\n";
    }
    else {
        print "NORMAL LICENSE"
    }

=head1 FUNCTIONS

=head2 has_flag($flag)

Check for specific flags for the current product license.

=head3 ARGUMENTS

=over

=item $flags - string

One of the following flag names:

=over

=item * dev

Check if the servers license is a developer license.

=item * trial

Check if the servers license is a trial license.

=item * vps

Check if the servers license if for VPS.

=back

=back

=head3 RETURNS

1 if the flag is set on the license, 0 otherwise.

=cut

sub has_flag {
    my ($flag) = @_;
    die 'Missing `flag` argument.'
      if !$flag;

    my @valid_flags = qw(dev trial vps);
    die 'Invalid `flag` argument: ' . $flag . '. You must use one of the following: ' . join( ', ', @valid_flags ) . '.'
      if !grep { $_ eq $flag } @valid_flags;

    if ( !defined $cpanel_flags ) {
        if ( defined $main::flags ) {
            $cpanel_flags = $main::flags;
        }
        else {
            require Cpanel::LoadModule;
            Cpanel::LoadModule::load_perl_module('Cpanel::CachedCommand');
            $cpanel_flags = Cpanel::CachedCommand::cachedcommand_multifile( ['/usr/local/cpanel/cpanel.lisc'], '/usr/local/cpanel/cpanel', '-F' );
        }
    }

    chomp $cpanel_flags;
    if ( grep { $flag eq $_ } split( m/\,/, $cpanel_flags ) ) {
        return 1;
    }

    return 0;
}

=head2 get_license_flags()

Read in the most recent cached license flags.

We read from the cache file for this:

    /var/cpanel/flagscache

These flags are for paid services attached to the cpanel license as flags.

=head3 RETURNS

A HASHREF where the keys are 'flags' in the license file and the value is 1

=cut

sub get_license_flags {

    require Cpanel::LoadFile;

    # This file is updated by cpsrvd
    my $cpanel_flags = Cpanel::LoadFile::load_if_exists($FLAGS_CACHE_FILE);

    return {} if !$cpanel_flags;
    chomp $cpanel_flags;
    my %flags;
    if ($cpanel_flags) {
        %flags = map { $_ => 1 } ( split( /,/, $cpanel_flags ) );
    }

    return \%flags;
}

1;
