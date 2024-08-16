package Cpanel::Binaries::Debian::AptCache;

# cpanel - Cpanel/Binaries/Debian/AptCache.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::Binaries::Debian::AptCache

=head1 DESCRIPTION

Wrapper around `apt-cache`.

=head1 SYNOPSIS

    my $bin = Cpanel::Binaries::Debian::AptCache->new();
    $bin->cmd( 'showpkg', 'package1' );
    ...

=cut

use cPstrict;

use parent 'Cpanel::Binaries::Role::Debian';

=head1 METHODS

=head2 bin_path($self)

Provides the path to the binary our parent SafeRunner should use.

=cut

sub bin_path ($self) {
    return '/usr/bin/apt-cache';
}

=head2 needs_lock

Allow exceptions to some calls that don't actually need exclusivity even if an (un)install is happening.

=cut

sub needs_lock ( $self, $action, @args ) {
    return 1 if grep { $action eq $_ } qw/ gencaches /;
    return 0;
}

=head2 show($self, $package)

Returns HASHREF of the output of `apt-cache show --no-all-versions $package`.

TODO: Switch to accepting @packages and returning arrayref of hashref.

=cut

sub show ( $self, $package ) {
    my $results = $self->_show( 1, $package );
    return if ref($results) ne 'ARRAY' || scalar(@$results) == 0;
    return $results->[0];
}

=head2 show_all_versions($self, @packages)

Returns ARRAYREF of HASHREF of the output of `apt-cache show @packages`.

=cut

sub show_all_versions ( $self, @packages ) {
    return $self->_show( 0, @packages );
}

sub _show ( $self, $no_all_versions, @packages ) {
    my @cmd = ('show');
    push @cmd, '--no-all-versions' if $no_all_versions;
    push @cmd, @packages;
    my $run = $self->cmd(@cmd);
    return if $run->{'status'};

    my @rv;
    my @records = split( "\n\n", $run->{'output'} );

    # There's a final line that will talk of suppressed records
    # if --no-all-versions is passed in
    pop @records if index( $records[-1], 'additional record' ) != -1;

    foreach my $output (@records) {
        my $cur_key;
        my %hr;
        my @lines = split( "\n", $output );
        foreach my $line (@lines) {
            my $cur_val;

            # Account for multiline values
            if ( $cur_key && index( $line, " " ) == 0 ) {
                $hr{ lc($cur_key) } .= $line;
                next;
            }

            # Set the KV pair
            my @exploded = split( ": ", $line, 2 );
            if ( scalar(@exploded) == 2 ) {
                ( $cur_key, $cur_val ) = @exploded;
                $hr{ lc($cur_key) } = $cur_val;
            }
        }

        push @rv, \%hr;
    }

    return \@rv;
}

1;
