package Install::Users;

# cpanel - install/Users.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use base qw( Cpanel::Task );

use strict;
use warnings;

use Cpanel::OS                 ();
use Cpanel::Sys::User          ();
use Cpanel::AcctUtils::Account ();

our $VERSION = '1.1';

=head1 DESCRIPTION

    Ensure cpanel system users are created and set properly.

=over 1

=item Type: Fresh Install, Sanity

=item Frequency: Always

=item EOL: never

=back

=cut

exit __PACKAGE__->runtask() unless caller;

sub new {
    my $proto = shift;
    my $self  = $proto->SUPER::new;

    $self->set_internal_name('users');
    $self->add_dependencies(qw(pre));

    return $self;
}

sub _cpanel_users {

    # Users need to be added to scripts/cpanel_initial_install as well
    return [
        qw{
          cpanel
          cpanelcabcache
          cpanellogin
          cpaneleximfilter
          cpaneleximscanner
          cpanelroundcube
          cpanelconnecttrack
          cpanelanalytics
        }
    ];
}

sub perform {
    my $self = shift;

    my $userhomes = '/var/cpanel/userhomes';
    if ( !-d $userhomes ) {
        if ( -e $userhomes ) {
            require Cpanel::FileUtils::Move;
            Cpanel::FileUtils::Move::safemv( $userhomes, "$userhomes.BACKUP" );
        }
        mkdir $userhomes;
    }

    chmod 0711, $userhomes;

    my $nologin = _nologin();

    # check and create cpanel users if missing
    for my $login ( @{ _cpanel_users() } ) {
        eval {
            Cpanel::Sys::User->new(
                login             => $login,
                basedir           => $userhomes,
                is_system_account => 1,
                shell             => '/usr/local/cpanel/bin/noshell',
                permissions       => 711,
            )->sanity_check( create_if_missing => 1, verbose => 1 );
        };
        print "Cannot fix user '$login': $@\n" if $@;
    }

    # Check and fix clamav user ( do not create it if missing )
    eval {
        Cpanel::Sys::User->new(
            login       => 'clamav',
            homedir     => '/usr/local/clamav',
            permissions => 711,
            shell       => $nologin,
        )->sanity_check();
    };
    print "Cannot fix user 'clamav': $@\n" if $@;

    # check and create named user if missing
    eval {
        my $perms = Cpanel::OS::var_named_permissions();
        Cpanel::Sys::User->new(
            login             => 'named',
            owner             => $perms->{'ownership'}[0],
            group             => $perms->{'ownership'}[1],
            is_system_account => 1,                                    # uid < UID_MIN
            homedir           => Cpanel::OS::dns_named_basedir(),
            permissions       => sprintf( "%o", $perms->{'mode'} ),    # It forces oct even if you start as it :(
            force             => 1
        )->sanity_check( create_if_missing => 1, verbose => 1 );
    };
    print "Cannot fix user 'named': $@\n" if $@;

    # check and create ftp user if account is missing only to preserve system default
    if ( !Cpanel::AcctUtils::Account::accountexists('ftp') ) {
        eval {
            Cpanel::Sys::User->new(
                login             => 'ftp',
                is_system_account => 1,            # uid < UID_MIN
                homedir           => '/var/ftp',
                permissions       => 755,
                shell             => $nologin,
                force             => 1
            )->sanity_check( create_if_missing => 1, verbose => 1 );
        };

        print "Cannot create user 'ftp': $@\n" if $@;
    }

    return 1;
}

sub _nologin {

    my @search = qw{ /sbin/nologin /usr/sbin/nologin /bin/false /usr/bin/false };
    foreach my $c (@search) {
        return $c if -x $c;
    }
    return q[/usr/local/cpanel/bin/noshell];    # last resort
}

1;

__END__
