package Whostmgr::DynamicUI::Filter;

# cpanel - Whostmgr/DynamicUI/Filter.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::Httpd::EA4         ();
use Cpanel::Config::LoadCpConf         ();
use Cpanel::Server::Type               ();
use Whostmgr::ACLS                     ();
use Whostmgr::Config::Services         ();
use Whostmgr::DynamicUI::Flags         ();
use Cpanel::Template::Plugin::Whostmgr ();

=head1 DESCRIPTION

Utility functions to evaluate flags inside dynamicui.conf files

=cut

=head1 SYNOPSIS

    use Whostmgr::DynamicUI::Filter;

     check_flag
        Evaluates a flag from dynamicui.conf

=cut

our $VERSION = '1.0';
my $logger;
my $cpconf_ref;
our $flags_stash;
our $system_vars;
my $dnsonly;

sub _logger {
    require Cpanel::Logger;
    return ( $logger ||= Cpanel::Logger->new() );
}

=head2 check_flag

=head3 Purpose

Evaluates a flag from dynamicui.conf

=head3 Arguments

=head4 Required

=over

=item 'flag' : string that represents the flag to be evaluated

=back

=head3 Returns

=over

=item the evaluated value of the flag

=back

=cut

sub check_flag {
    my $flag = shift;
    return if !$flag;

    if ( $flag =~ m/^CPCONF=/ ) {
        $cpconf_ref ||= Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
        my ($var) = ( split( m/=/, $flag ) )[1];
        return $cpconf_ref->{$var};
    }
    elsif ( $flag =~ m/^ACL=/ ) {
        my ($var) = ( split( m/=/, $flag ) )[1];
        return Whostmgr::ACLS::checkacl($var);
    }
    elsif ( $flag =~ m/^ea\s+/ ) {
        my ( $op, $version ) = ( split( m/\s+/, $flag ) )[ 1, 2 ];
        my $ea_version = _get_ea_version();

        my $answer;
        if ( $op eq '<' ) {
            $answer = $ea_version < $version;
        }
        elsif ( $op eq '<=' ) {
            $answer = $ea_version <= $version;
        }
        elsif ( $op eq '==' ) {
            $answer = $ea_version == $version;
        }
        elsif ( $op eq '>' ) {
            $answer = $ea_version > $version;
        }
        elsif ( $op eq '>=' ) {
            $answer = $ea_version >= $version;
        }

        return $answer;
    }

    _init_system_vars() unless $system_vars;
    return $system_vars->{$flag} if exists $system_vars->{$flag};

    if ( !exists $flags_stash->{$flag} ) {
        _init_flag_variable($flag);
    }
    return $flags_stash->{$flag};
}

sub _get_ea_version {
    return Cpanel::Config::Httpd::EA4::is_ea4() ? 4 : 0;
}

sub _init_system_vars {
    $system_vars = {

        # This *seems* to be unused, but we retain it just in case:
        dnsonly => Cpanel::Server::Type::is_dnsonly() ? 1 : 0,

        Whostmgr::DynamicUI::Flags::get_system_variables(),
    };

    return;
}

sub _init_flag_variable {
    my ($var) = @_;

    $flags_stash ||= {};

    if ( $var =~ /_enabled$/ && !defined $flags_stash->{$var} ) {    #_enabled is a service
        $flags_stash->{$var} = 0;
        Whostmgr::Config::Services::get_enabled( $flags_stash, $var );
    }
    elsif ( $var eq 'addons' ) {
        my $plugin       = Cpanel::Template::Plugin::Whostmgr->new();
        my $plugins_data = Cpanel::Template::Plugin::Whostmgr->plugins_data();
        $flags_stash->{'addons'} = ref $plugins_data && scalar @{$plugins_data};
    }

    return;
}

1;
