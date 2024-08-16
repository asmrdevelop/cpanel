package Install::BashTimestamps;

# cpanel - install/BashTimestamps.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use base qw( Cpanel::Task );

use strict;
use warnings;
use Cpanel::FileUtils::Lines     ();
use Cpanel::FileUtils::TouchFile ();

our $VERSION = '1.0';

=head1 DESCRIPTION

    Add HISTTIMEFORMAT environment variable to /etc/profile.d/bash_timestamps.sh

=over 1

=item Type: Fresh Install, sanity

=item Frequency: once

    Run once or when needed if file was altered.

    Note: could use already_performed

=item EOL: never

=back

=cut

exit __PACKAGE__->runtask() unless caller;

sub new {
    my $proto = shift;
    my $self  = $proto->SUPER::new;

    $self->set_internal_name('bash_timestamps');

    return $self;
}

sub _add_HISTTIMEFORMAT_if_necessary {
    my $bashrc = '/etc/profile.d/bash_timestamps.sh';
    my $ts_txt = <<EOM;

# Enable timestamps in bash history
export HISTTIMEFORMAT="%F %T "
EOM
    if ( !-e $bashrc ) {
        Cpanel::FileUtils::TouchFile::touchfile($bashrc);
    }

    if (   !Cpanel::FileUtils::Lines::has_txt_in_file( $bashrc, 'HISTTIMEFORMAT' )
        && !Cpanel::FileUtils::Lines::appendline( $bashrc, $ts_txt ) ) {
        warn 'Failed to add HISTTIMEFORMAT to /etc/bashrc';
        return;
    }

    return 1;
}

sub perform {
    my $self = shift;
    if ( !_add_HISTTIMEFORMAT_if_necessary() ) {

        # already warned, would be redundant to do it again
    }

    return 1;
}

1;

__END__
