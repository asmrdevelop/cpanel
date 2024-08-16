package Cpanel::IpTables;

# cpanel - Cpanel/IpTables.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent 'Cpanel::XTables';

our $IPTABLES  = '/sbin/iptables';
our $IP6TABLES = '/sbin/ip6tables';
use List::Util               ();
use Cpanel::SafeRun::Errors  ();
use Cpanel::Version::Compare ();
use Cpanel::CachedCommand    ();
use Cpanel::Sys::Uptime      ();
use Cpanel::PwCache          ();    # PPI USE OK - Will always be loaded by CachedCommand
###########################################################################
#
# Method:
#   _init
#
# Description:
#   This module create an iptables chain
#
# Parameters:
#   chain       - Required. The name of the chain
#   ipversion   - Required. The version of the IP protocol
# Returns:
#   A Cpanel::IpTables object
#
sub _init {
    my ( $self, %OPTS ) = @_;

    $self->{'ipversion'} = $OPTS{'ipversion'} || 4;
    $self->{'binary'}    = $self->{'ipversion'} == 6 ? $IP6TABLES : $IPTABLES;

    # Make sure iptables is working once per boot or binary mtime change
    # This is almost moot though since we don't support Cent5 anymore
    my $version_text = Cpanel::CachedCommand::cachedmcommand( Cpanel::Sys::Uptime::get_uptime(), $self->{'binary'}, '--version' );

    if ( !$version_text ) {
        die "Failed to obtain iptables version.";
    }

    my $full_version;
    ( ( $full_version, $self->{'version'} ) = $version_text =~ m{(([0-9]+\.[0-9]+)\.[0-9]+)} )[0] || die "$self->{'binary'} failed to execute.";

    $self->{'args'} = Cpanel::Version::Compare::compare( $full_version, '>=', '1.4.20' ) ? [ '-w', $Cpanel::XTables::TIMEOUT ] : [];

    return $self;
}

###########################################################################
#
# Method:
#   init_chain
#
# Description:
#   Create the chain in iptables.
#   Any previous rules and references to this chain
#   will be purge and the chain will be reset to
#   a fresh state
#
sub _create_chain {
    my ($self) = @_;

    $self->exec_checked_calls(
        [
            [ '-N', $self->{'chain'} ],
        ],
    );

    return 1;
}

###########################################################################
#
# Method:
#   attach_chain
#
# Description:
#   Attach the chain to a built-in target
#   Valid targets are: INPUT, OUTPUT, FORWARD
#
sub _attach_chain {
    my ( $self, $target ) = @_;

    my @calls = ( [ '-I', $target, '-j', $self->{'chain'} ] );

    my $chain_ref = $self->get_builtin_chains_that_reference_chain();
    if ( $chain_ref->{$target} ) {
        unshift @calls, [ '-D', $target, '-j', $self->{'chain'} ];
    }

    $self->exec_checked_calls( \@calls );

    return 1;
}

###########################################################################
#
# Method:
#   get_builtin_chains_that_reference_chain
#
# Description:
#   Returns a hashref of builtin chains that
#   reference the chain that the object was
#   initialized with.
#
#   For easy lookups this returns a hashref
#   instead of an arrayref
#
#   Example hashref (values are always 1):
#    {
#      'INPUT'  => 1,
#      'OUTPUT' => 1,
#    }
#
sub get_builtin_chains_that_reference_chain {
    my ($self) = @_;
    my %tables;
    my $rules_ref = $self->get_all_rules();
    foreach my $rule ( @{$rules_ref} ) {
        if ( $rule->[0] eq '-A' ) {
            if ( my $chain = $self->_arg_after_key( $rule, 'j' ) ) {
                if ( $chain eq $self->{'chain'} ) {
                    $tables{ $rule->[1] } = 1;
                }
            }
        }
    }

    return \%tables;
}

###########################################################################
#
# Method:
#   chain_exists
#
# Description:
#   Check to see if the object's chain exists in iptables
#
sub _chain_rules_include_chain {
    my ( $self, $rules_ref ) = @_;

    return if !defined $rules_ref;

    return ( List::Util::first { $_->[0] eq '-N' } @{$rules_ref} ) ? 1 : 0;
}

###########################################################################
#
# Method:
#   _remove_chain_from_all_builtin_chains
#
# Description:
#   Remove the chain from all built in chains
#
sub _remove_chain_from_all_builtin_chains {
    my ($self) = @_;

    my @calls;
    my $rules_ref = $self->get_all_rules();
    foreach my $rule ( @{$rules_ref} ) {
        if ( $rule->[0] eq '-A' ) {
            if ( my $chain = $self->_arg_after_key( $rule, 'j' ) ) {
                if ( $chain eq $self->{'chain'} ) {
                    $rule->[0] = '-D';
                    push @calls, $rule;
                }
            }
        }
    }

    $self->exec_checked_calls( \@calls );
    $self->exec_checked_calls( [ [ '-F', $self->{'chain'} ], [ '-X', $self->{'chain'} ] ] );

    return 1;
}

###########################################################################
#
# Method:
#   exec_checked_calls
#
# Description:
#   Execute a list of of iptables calls and
#   die if any of them fail.
#
sub exec_checked_calls {
    my ( $self, $calls ) = @_;

    local $ENV{'TZ'} = ':UTC';
    my @results;
    foreach my $call ( @{$calls} ) {
        my $output = Cpanel::SafeRun::Errors::saferunallerrors( $self->{'binary'}, @{ $self->{'args'} }, @{$call} );
        $self->_die_on_iptables_exec_failure( $call, $output, $? ) if $?;
        push @results, $output;
    }

    return \@results;
}

sub get_rules {
    my ( $self, $chain ) = @_;

    local $ENV{'TZ'} = ':UTC';
    my @rules;
    if ( $self->{'version'} >= 1.4 ) {
        my @call   = ( '--list-rules', ( $chain ? $chain : () ) );
        my $output = Cpanel::SafeRun::Errors::saferunallerrors( $self->{'binary'}, @{ $self->{'args'} }, @call );

        if ( my $CHILD_ERROR = $? ) {
            my $error_code = $CHILD_ERROR >> 8;
            if ( $error_code != 1 ) {

                # exit code for No chain is always 1
                # It is important that we die here otherwise we may end up
                # clearing the chain because we think it does not exist due
                # to a timeout with the xtables lock
                #
                # xtables lock failures usually exit with error code 4
                # and we need to die
                $self->_die_on_iptables_exec_failure( \@call, $output, $? );
            }
        }
        foreach my $rule ( split( m{\n}, $output ) ) {
            push @rules, [ split( m{ }, $rule ) ];
        }
    }
    else {
        # This code is to support C5 and likely can go away
        my ( $parsed_chain, $parsed_policy );
        foreach my $rule ( split( m{\n}, Cpanel::SafeRun::Errors::saferunallerrors( $self->{'binary'}, '--list', ( $chain ? $chain : () ), '--numeric', '--verbose', '--exact', '--line-numbers' ) ) ) {

            if ( $rule =~ m/^Chain[ \t]+(\S+)/ ) {
                $parsed_chain = $1;
                if ( $parsed_chain !~ m{^(?:INPUT|FORWARD|OUTPUT)$} ) {
                    push @rules, [ '-N', $parsed_chain ];
                }
                if ( $rule =~ m{Policy[ \t]+(\S+)} ) {
                    $parsed_policy = $1;
                    push @rules, [ '-P', $parsed_chain, $parsed_policy ];
                }
            }
            elsif ( $rule =~ m{^[0-9]+ } ) {
                my @split = split( m{[ ]+}, $rule );
                shift @split;    # $num
                shift @split;    # $pkts
                shift @split;    # $bytes
                my ( $target, $proto );
                if ( $split[0] =~ m{^(?:all|tcp|udp|icmp)$} ) {
                    $proto = shift @split;
                }
                else {
                    $target = shift @split;
                    $proto  = shift @split;
                }
                my ( $opt, $in, $out, $source, $dest, @rest ) = @split;

                if ($target) {
                    if ( $proto eq 'all' && $source eq '0.0.0.0/0' && $dest eq '0.0.0.0/0' ) {
                        push @rules, [ '-A', $parsed_chain, '-j', $target ];
                    }
                    elsif ( $dest eq '0.0.0.0/0' ) {
                        push @rules, [ '-A', $parsed_chain, '-s', $source, '-j', $target ];
                    }
                    elsif ( $source eq '0.0.0.0/0' ) {
                        push @rules, [ '-A', $parsed_chain, '-d', $dest, '-j', $target ];
                    }
                }
            }
            else {
                #print STDERR "[$rule]\n";
            }

        }
    }
    return \@rules;
}

# Returns the value of an arg after a specific key
# EX $self->_arg_after_key(['bob','--version','2.0','cat'],'version') will return '2.0'
sub _arg_after_key {
    my ( $self, $arr_ref, $key ) = @_;

    my $seen_wanted = 0;
    foreach my $value ( @{$arr_ref} ) {
        if ($seen_wanted) {
            return $value;
        }
        elsif ( $value eq "-$key" || $value eq "--$key" ) {
            $seen_wanted = 1;
        }
    }
    return;
}

sub _die_on_iptables_exec_failure {
    my ( $self, $call, $output, $child_error ) = @_;
    my $child_status = $SIG{'CHLD'} && $SIG{'CHLD'} eq 'IGNORE' ? 0 : $child_error;
    if ( $child_status != 0 ) {
        require Cpanel::ChildErrorStringifier;
        my $autopsy = $child_status == -1 ? 'Failed to execute' : Cpanel::ChildErrorStringifier->new($child_status)->autopsy();
        $output //= "";
        die "[iptables] $self->{'binary'} @{$self->{'args'}} @{$call} failed: $output: $autopsy";
    }
    return 1;

}

sub supported_ip_versions {
    return ( 4, 6 );
}

sub clear_firewall ($self) {
    return $self->exec_checked_calls( [ ['-F'] ] );
}

1;
