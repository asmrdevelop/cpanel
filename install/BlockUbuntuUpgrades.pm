package Install::BlockUbuntuUpgrades;

# cpanel - install/BlockUbuntuUpgrades.pm           Copyright 2022 cPanel, L.L.C.
#                                                            All rights Reserved.
# copyright@cpanel.net                                          http://cpanel.net
# This code is subject to the cPanel license.  Unauthorized copying is prohibited

use base qw( Cpanel::Task );

use cPstrict;

use Cpanel::OS ();

our $VERSION = '1.0';

=head1 DESCRIPTION

    Block Ubuntu upgrades.

=over 1

=item Type: Sanity

=item Frequency: always

=item EOL: never

=back

=cut

use constant RELEASE_UPGRADES_FILE => q[/etc/update-manager/release-upgrades];

exit __PACKAGE__->runtask() unless caller;

sub new ($proto) {

    my $self = $proto->SUPER::new;
    $self->set_internal_name('block_ubuntu_upgrades');

    return $self;
}

sub perform ($self) {

    return 1 unless Cpanel::OS::is_apt_based();

    $self->update_release_upgrades();

    return 1;
}

sub update_release_upgrades ($self) {

    my $f = RELEASE_UPGRADES_FILE;

    return unless -e $f;

    my @lines;
    {
        local $/;
        if ( open( my $fh, '<', $f ) ) {
            @lines = split( /\n/, <$fh> // '' );
        }
        else {
            return;
        }
    }

    my $in_default;
    my $was_updated;
    foreach my $l (@lines) {
        if ( $l =~ qr{^\s*\[(\w+)\]}a ) {
            if ( $1 eq 'DEFAULT' ) {
                $in_default = 1;
            }
            else {
                $in_default = 0;
            }
            next;
        }
        next unless $in_default;

        # no need for an update
        return 2 if $l =~ m{^\s*Prompt\s*=\s*never}a;

        if ( $l =~ s{^\s*Prompt\s*=\s*(?:normal|lts)}{Prompt=never} ) {
            $was_updated = 1;
            last;
        }
    }

    return unless $was_updated;

    open( my $fh, '>', $f ) or die $!;
    print {$fh} join( "\n", @lines, '' );

    return 1;
}

1;
