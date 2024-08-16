package Whostmgr::Accounts::Shell;

# cpanel - Whostmgr/Accounts/Shell.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Exception          ();
use Cpanel::Passwd::Shell      ();
use Cpanel::Hooks              ();
use Cpanel::PwCache::Helpers   ();
use Cpanel::PwCache::Build     ();
use Cpanel::Debug              ();
use Cpanel::Config::LoadCpConf ();
use Cpanel::OrDie              ();
use Cpanel::PwCache::Clear     ();
use Cpanel::ServerTasks        ();
use Cpanel::Shell              ();
use Cpanel::SafeRun::Simple    ();
use Cpanel::Binaries           ();

use Try::Tiny;

my $PACKAGE = __PACKAGE__;

sub set_shell {
    my ( $users, $new_shell ) = @_;

    my $want_scalar_return = 0;
    my %SHELLS;

    if ( !ref $users ) {
        $want_scalar_return = 1;    # compromise to keep old code working
        my $user = $users;
        $users  = [ [ $user, $new_shell ] ];
        %SHELLS = ( $user => Cpanel::Shell::get_shell($user) );
    }
    elsif ( scalar @{$users} > 5 ) {
        Cpanel::PwCache::Helpers::no_uid_cache();    #uid cache only needed if we are going to make lots of getpwuid calls
        Cpanel::PwCache::Build::init_pwcache();
        my $pwcache_ref = Cpanel::PwCache::Build::fetch_pwcache();
        %SHELLS = map { $_->[0] => $_->[8] } @$pwcache_ref;
    }
    else {
        foreach my $user_ref ( @{$users} ) {
            my ($user) = @{$user_ref};
            $SHELLS{$user} = Cpanel::Shell::get_shell($user);
        }
    }

    my @ret;
    my @tasks;
    my $cpconf_ref = Cpanel::Config::LoadCpConf::loadcpconf();

    foreach my $user_ref ( @{$users} ) {
        my ( $user, $new_shell ) = @{$user_ref};

        my $current_shell = $SHELLS{$user};

        my ( $shell_ok, $shell_is_valid ) = Cpanel::OrDie::convert_die_to_multi_return( sub { Cpanel::Shell::is_valid_shell($new_shell) } );

        if ( !defined $current_shell ) {

            # No logger here because error logged in get_shell
            push @ret, { 'status' => 0, 'user' => $user, 'statusmsg' => 'Invalid account specified.' };
        }
        elsif ( !$new_shell ) {
            Cpanel::Debug::log_warn('Invalid shell specified');
            push @ret, { 'status' => 0, 'user' => $user, 'statusmsg' => 'Invalid shell specified.' };
        }
        elsif ( $new_shell eq $current_shell ) {
            push @ret, { 'status' => 0, 'user' => $user, 'statusmsg' => "User ${user}'s shell already set to $current_shell" };
        }
        elsif ( !$shell_ok || !$shell_is_valid ) {
            push @ret, { 'status' => 0, 'user' => $user, 'statusmsg' => $shell_is_valid };
        }
        else {
            my ( $pre_hook_result, $hook_msgs ) = Cpanel::Hooks::hook(
                {
                    'category' => 'Whostmgr',
                    'event'    => 'Accounts::set_shell',
                    'stage'    => 'pre',
                    'blocking' => 1,
                },
                {
                    'new_shell'     => $new_shell,
                    'current_shell' => $current_shell,
                    'user'          => $user,
                }
            );
            if ( !$pre_hook_result ) {
                my $hooks_msg = int @{$hook_msgs} ? join "\n", @{$hook_msgs} : '';
                push @ret, { 'status' => 0, 'user' => $user, 'statusmsg' => "Hook denied modification of account: $hooks_msg" };
                next;
            }

            my $status = 1;
            my $rawout = '';
            try {
                Cpanel::Passwd::Shell::update_shell_without_acctlock( 'user' => $user, 'shell' => $new_shell );
                $rawout = 'Shell changed';    # for legacy compat
            }
            catch {
                $status    = 0;
                $new_shell = $current_shell;
                $rawout .= Cpanel::Exception::get_string($_);
            };

            Cpanel::Hooks::hook(
                {
                    'category' => 'Whostmgr',
                    'event'    => 'Accounts::set_shell',
                    'stage'    => 'post',
                },
                {
                    'new_shell'     => $new_shell,
                    'current_shell' => $current_shell,
                    'user'          => $user,
                    'rawout'        => $rawout,
                }
            );
            if ( !$status ) {
                push @ret, { 'status' => 0, 'user' => $user, 'statusmsg' => "Shell not modified due to error: $rawout" };
                next;
            }

            # Success!

            if ( $new_shell =~ m{(?:no|jail)shell} && $current_shell =~ m{(?:no|jail)shell} ) {

                # No need to update anything since noshell and jailshell both
                # make use of jails
            }
            elsif ( $new_shell =~ m{(?:no|jail)shell} || $current_shell =~ m{(?:no|jail)shell} ) {
                push @tasks, "update_users_jail $user";                                    # will mount/umount and update crontab shell as needed
                push @tasks, "update_users_vhosts $user" if $cpconf_ref->{'jailapache'};
            }

            # Kill off any existing user shell sessions
            if ( $new_shell =~ m{\/noshell$} ) {
                kill_shell_sessions( $user, $current_shell );
            }

            push @ret, { 'status' => 1, 'user' => $user, 'statusmsg' => $rawout };
        }
    }

    push @tasks, 'apache_restart' if @tasks && $cpconf_ref->{'jailapache'};

    Cpanel::ServerTasks::queue_task( ['ApacheTasks'], @tasks ) if @tasks;

    #TODO: Find/create a way to clear just this user's cache.
    Cpanel::PwCache::Clear::clear_global_cache();

    #
    #  This is a compromise to keep the existing code working
    #  It would be better if everything passed this function an
    #  arrayref.
    #
    if ($want_scalar_return) {
        return $ret[0]->{'statusmsg'};
    }

    return \@ret;
}

sub is_unrestricted_shell {
    my ($shell) = @_;
    if ( $shell =~ m/(?:jailshell|noshell|nologin|false|shutdown|sync)$/ ) {
        return 0;
    }
    elsif ( -x $shell ) {
        return 1;
    }
    return 0;
}

sub has_unrestricted_shell {
    my ($user) = @_;
    my $user_shell = Cpanel::Shell::get_shell($user);
    if ( $user_shell && is_unrestricted_shell($user_shell) ) {
        return 1;
    }
    return 0;
}

sub has_jail_shell {
    my ($user) = @_;
    my $user_shell = Cpanel::Shell::get_shell($user);
    if ( $user_shell && $user_shell =~ m{jailshell} ) {
        return 1;
    }
    return 0;
}

# Does the user have shell access at all?
sub has_shell {
    my ($user) = @_;
    my $user_shell = Cpanel::Shell::get_shell($user);
    if ( $user_shell && ( $user_shell =~ m{jailshell} || is_unrestricted_shell($user_shell) ) ) {
        return 1;
    }
    return 0;
}

sub kill_shell_sessions {
    my ( $user, $shell ) = @_;

    return if !$user || !$shell;

    my ($shell_name) = $shell =~ m{\/(\w+)$};
    my $pkill_bin = Cpanel::Binaries::path(q{pkill});

    if ( !-x $pkill_bin ) {
        Cpanel::Debug::log_warn('Unable to locate suitable pkill binary for killing active shell sessions');
        return;
    }

    Cpanel::SafeRun::Simple::saferunallerrors( $pkill_bin, '-KILL', '-u', $user, '-f', $shell_name );

    return;
}

1;
