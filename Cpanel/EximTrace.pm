package Cpanel::EximTrace;

# cpanel - Cpanel/EximTrace.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::EximTrace

=head1 SYNOPSIS

    my $trace_hr = Cpanel::EximTrace::deep_trace('foo@bar.org');

=head1 DESCRIPTION

This module contains logic to parse Exim’s delivery trace.

=cut

#----------------------------------------------------------------------

use Cpanel::AcctUtils::DomainOwner::Tiny ();
use Cpanel::ChildErrorStringifier        ();
use Cpanel::Exec                         ();
use Cpanel::Hostname                     ();
use Cpanel::InternalDBS                  ();
use Cpanel::Validate::EmailRFC           ();
use Cpanel::Exim::Options                ();
use Whostmgr::AcctInfo::Owner            ();

use constant _EXIM_BIN => '/usr/sbin/sendmail';

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $route_hr = generate_trace_table( $ADDRESS )

The original function to do this trace. It returns a hash reference:

=over

=item * C<startaddress> - The first address routed.

=item * C<route> - A hash reference of addresses and destinations where
that address goes. Each address’s hash value is a reference to an array
of destinations; each destination is a hash reference of attributes that
describes the destination.

=back

=cut

sub generate_trace_table {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my $address = shift;

    die 'Need REMOTE_USER to be set!' if !defined $ENV{REMOTE_USER};

    $address = Cpanel::Validate::EmailRFC::scrub($address);
    $address =~ s/^\-+//;

    if ( $address !~ /\@/ ) {
        $address .= '@' . Cpanel::Hostname::gethostname();
    }

    my @internal_dbs;

    my %ROUTE;
    my %follow_routes = ( $address => 1 );
    my $aliasfile;
    my $current_address = '';
    my $router          = '';
    my $dnsfailure      = '';
    my $startaddress;
    my $is_failure;
    my $indicated_bounce;
    my @routers;

    my %blackholed;
    my $wait_until_next_address;

    my ( $exim_pid, $exim_fh ) = _get_exim_pid_and_filehandle($address);

  LINE_LOOP:
    while ( my $LINE = readline $exim_fh ) {
        chomp $LINE;

        if ( -1 != index( $LINE, '>>>>>>>>>>>>' ) ) {

            # Store last routing match
            if ( $current_address && scalar @routers && $follow_routes{$current_address} ) {

                if ( $routers[0]->{router} && $routers[0]->{router} =~ /lookuphost|fail_remote_domains/ ) {

                    # Remote delivery details are always visible if the path leading to the remote delivery attempt is visible
                    push @{ $ROUTE{$current_address} }, @routers;
                }
                else {
                    # This is a local delivery and routes may be private
                    if ( _routing_traceable($current_address) ) {

                        # Add subsequent addresses to follow_routes if current address is visible
                        push @{ $ROUTE{$current_address} }, @routers;
                        foreach my $route (@routers) {
                            next if $route->{router} && $route->{router} =~ /lookuphost|fail_remote_domains|blackhole/;
                            next if $route->{result} eq 'local delivery';
                            $follow_routes{ $route->{result} } = 1;
                        }
                    }
                    else {

                        # Set a fake route for addresses that can't be traced.
                        $ROUTE{$current_address} = [ { 'mailbox' => $current_address, 'router' => 'untraceable route', 'result' => 'local delivery' } ];
                    }
                }
            }

            # reset variables
            $is_failure       = 0;
            $indicated_bounce = 0;
            $aliasfile        = '';
            $router           = '';
            $dnsfailure       = '';
            @routers          = ();
        }

        # First list of routing to a new address
        if ( $LINE =~ /^routing\s+(\S+)/ ) {
            my $new_address = $1;

            if ( !length $startaddress ) {
                $startaddress = $new_address;
            }
            elsif ( $current_address ne $new_address ) {
                if ( $ROUTE{$new_address} ) {
                    $wait_until_next_address = 1;
                    next LINE_LOOP;
                }
            }

            $current_address = $new_address;

            $wait_until_next_address = 0;

            $router = '';
        }
        elsif ($wait_until_next_address) {
            next LINE_LOOP;
        }

        # First line of considering a new router for the current address
        elsif ( $LINE =~ /^\-+\>\s+(\S+)\s*router\s+\<\-+/ ) {
            $router = $1;

            if ( $router eq 'userforward' ) {
                ( $LINE, my @new ) = _parse_userforward_router($exim_fh);
                push @routers, @new;
                redo LINE_LOOP;    #To re-parse $LINE
            }
        }

        # A domains or aliases file (e.g., /etc/valiases/DOMAIN)
        elsif ( $LINE =~ /^\s+in\s+(\S+)/ ) {
            if ( !@internal_dbs ) {
                @internal_dbs = map { "/etc/$_->{'file'}" } @{ Cpanel::InternalDBS::get_all_dbs() };
            }

            if ( !grep { $_ eq $1 } @internal_dbs ) {
                $aliasfile = $1;
            }
        }

        # Indicate a local delivery.
        # (Would it be better to read the “routed by …” block??)
        elsif ( $LINE =~ /^(\S+)\s+router\s+called\s+for\s+(\S+)/ ) {
            my $mailbox = $2;
            my $router  = $1;
            next if ( $router !~ /(?:virtual_?(?:sa|boxtrapper)?_?user|local)/i );
            if ( !$blackholed{$mailbox} ) {
                my $new = { mailbox => $mailbox, result => 'local delivery', router => $router };
                push( @routers, $new );
            }
        }

        # ??
        elsif ( $LINE =~ /^(\S+)\s+router\s+generated\s+(.+)/ ) {
            my $new = { aliasfile => $aliasfile, result => $2, router => $1 };
            push( @routers, $new );
        }

        # blackholed delivery
        # except where that blackholed delivery is for loop prevention
        elsif ( $LINE =~ /^address\s+:blackhole:d/ && $router ne 'has_alias_but_no_mailbox_discarded_to_prevent_loop' ) {
            my $new = { aliasfile => $aliasfile, result => 'discard', route => 'blackhole' };

            push @routers, $new;

            # :blackhole: clobbers everything after it.
            $blackholed{$current_address} = 1;

            $wait_until_next_address = 1;
        }

        # bounce -- whether intended or not
        elsif ( $LINE =~ /^parse_forward_list: \s+ :fail: \s* (.*)/x ) {
            $is_failure = 1;

            if ( $router eq 'fail_remote_domains' ) {
                push @routers, {
                    error   => 1,
                    router  => $router,
                    result  => $dnsfailure,
                    message => $1,
                };
            }
            else {
                push @routers, {
                    result  => 'bounce',
                    router  => $router,
                    message => $1,
                };

                $indicated_bounce = 1;
            }
        }

        # Another catcher for bounces.
        elsif ( $LINE =~ /^(\S+)\s+(?:router)?\s*forced\s+address\s+failure/ ) {
            my $failure = $LINE;

            # fail_remote_domains errors will already have been recorded.
            if ( $1 ne 'fail_remote_domains' && !$indicated_bounce ) {
                push( @routers, { result => 'bounce', message => q<>, router => $1, error => 1 } );
                $indicated_bounce = 1;
            }
        }

        # So that we see DNS lookup failures.
        elsif ( $LINE =~ /DNS lookup.*gave/ ) {
            $dnsfailure = $LINE;
        }

        # superfluous?
        elsif ( $LINE =~ /^(\S+)\s+(?:router)?\s*forced\s+address\s+failure/ ) {
            if ( !length $is_failure ) {
                my $failure = $LINE;
                my $new     = { result => $failure, router => $1, error => 1 };
                push( @routers, $new );
            }
        }

        # superfluous?
        elsif ( $LINE =~ /^routed\s+by\s+(.*)/ ) {
            $router = $1;
            $router =~ s/\s*router$//g;
        }

        else {
            my $new;
            if ( $LINE =~ /^\Q$router\E\s+router:\s+(\S+)/ ) {
                $new = { result => $1, router => $router, message => $dnsfailure };
            }

            elsif ( $router ne '' && $LINE =~ /^\s+:defer:\s+(.*)/ ) {
                $new = { result => $1, router => $router };
            }
            elsif ( $router ne '' && $LINE =~ /^\s+host\s+(.*)/ ) {
                $new = { result => $1, router => $router };
            }

            # e.g., if an email account’s delivery is suspended
            elsif ( $LINE =~ /rda_interpret:\s+.*\s+error=(.+)/ ) {
                if ( $1 ne 'NULL' ) {
                    $new = { error => 1, result => $1 };
                }
            }

            if ($new) {
                push @routers, $new;
            }
        }
    }

    close $exim_fh;

    # NB: The child process can exit nonzero on success.
    local $?;
    waitpid $exim_pid, 0;

    my $childerr = Cpanel::ChildErrorStringifier->new( $?, _EXIM_BIN() );

    if ( my $sig = $childerr->signal_code() ) {
        warn $childerr->autopsy();
    }

    my $exim_trace_tbl = {
        'startaddress' => $startaddress,
        'route'        => \%ROUTE
    };

    return $exim_trace_tbl;

}

#----------------------------------------------------------------------

=head2 my $trace_hr = deep_trace( $ADDRESS )

Returns a hash reference. Hash members are:

=over

=item * C<type> - The type of trace node. One of:

=over

=item * C<local_delivery>: The hash will also include a C<mailbox> to indicate
which local mailbox will receive the message.

=item * C<remote_delivery>: The hash will also include a C<mx> structure to
indicate where the server will send the message via SMTP. The C<mx> is a list
of hash references, each of which contains C<priority>, C<hostname>, and C<ip>.

=item * C<routed>: The hash will include an C<address> and either
C<destinations> or the C<recursion> flag.

=item * C<bounce>: The hash will also include a C<message> that the server
will send with the SMTP rejection.

=item * C<defer>: The hash will also include a C<message> that the server
will give to the message sender.

=item * C<discard>

=item * C<command>: The hash will also include a C<command> to indicate the
system command that will receive the message.

=item * C<error>: The hash will include C<result> and, possibly, C<message>.

=back

=item * C<address> - The address being routed.

=item * C<destinations> - If present, a reference to an array of
destinations for the C<address>. Each destination is a hash reference that
indicates an error, has a C<type> to indicate the end of routing, or contains
its own C<address> to indicate further routing.

=item * C<recursion> - If present, indicates that the present address is
a recursive redirect loop. No C<destinations> are given since the C<address>
will already have occurred in the trace.

=item * C<aliasfile> - If present, the file on disk where Exim looked for
aliases for the current C<address>.

=back

=cut

sub deep_trace {
    my ($recipient) = @_;

    my $response = generate_trace_table($recipient);

    my $route_hr = $response->{'route'};

    my %address_seen;

    my $trace_hr = {
        type    => 'routed',
        address => $response->{'startaddress'},
    };

    sub {
        my ($cur_trace_node) = @_;

        my $address = $cur_trace_node->{'address'};

        my @destinations;
        $cur_trace_node->{'destinations'} = \@destinations;

        $address_seen{$address} = 1;

        my $dest_node_list = $route_hr->{$address} or do {
            warn "Missing address “$address” in trace! Skipping …\n";
            return;
        };

        my $first_dest = $dest_node_list->[0];

        my $router = $first_dest->{'router'} || q<>;

        # remote delivery
        if ( $router eq 'dkim_lookuphost' || $router eq 'lookuphost' ) {
            my @mx_list = map { $_->{'result'} } @$dest_node_list;

            for my $mx (@mx_list) {
                if ( $mx =~ m<\A (\S+) \s+ \[ (\S+) \] (?:\s+ MX=([0-9]+))? (?:\s+ dnssec=([a-zA-Z]+))? \z>x ) {
                    $mx = {
                        hostname => $1,
                        ip       => $2,
                        priority => $3,
                        dnssec   => $4,
                    };
                }
                else {
                    warn "Unparsable MX line ($mx) - did Exim change?";
                }
            }

            push @destinations, {
                type => 'remote_delivery',
                mx   => \@mx_list,
            };
        }

        # error
        elsif ( $first_dest->{'error'} ) {
            $first_dest->{'type'} = 'error';

            # There’s no point in giving these to the caller.
            delete @{$first_dest}{ 'error', 'router' };

            push @destinations, $first_dest;
        }

        # redirected to one or more other addresses
        else {
            for my $this_node (@$dest_node_list) {
                if ( grep { $_ eq $this_node->{'result'} } 'defer', 'bounce' ) {
                    push @destinations, {
                        type    => $this_node->{'result'},
                        message => $this_node->{'message'},
                    };
                }
                elsif ( $this_node->{'result'} eq 'local delivery' ) {
                    push @destinations, {
                        type    => 'local_delivery',
                        mailbox => $this_node->{'mailbox'},
                    };
                }
                elsif ( $this_node->{'result'} eq 'discard' ) {
                    push @destinations, {
                        type      => $this_node->{'result'},
                        aliasfile => $this_node->{'aliasfile'},
                    };
                }
                elsif ( $this_node->{'result'} =~ m<\A \| (.+)>x ) {
                    push @destinations, {
                        type    => 'command',
                        command => $1,
                    };
                }
                else {
                    my $new_address = $this_node->{'result'};

                    my $new_trace_node = {
                        type      => 'routed',
                        address   => $new_address,
                        aliasfile => $this_node->{'aliasfile'},
                    };

                    push @destinations, $new_trace_node;

                    if ( $address_seen{$new_address} ) {
                        $new_trace_node->{'recursion'} = 1;
                    }
                    elsif ( $this_node->{'result'} ) {
                        __SUB__->($new_trace_node);
                    }
                }
            }
        }
      }
      ->($trace_hr);

    return $trace_hr;
}

sub _routing_traceable {
    my $test_email = shift;
    return 0 unless $test_email =~ tr/@//;

    if ( $ENV{REMOTE_USER} =~ tr/@// ) {

        # Webmail access. Only the current account's routing information will be visible
        return 1 if ( $test_email eq $ENV{REMOTE_USER} );
    }
    else {

        # Allow system_user@hostname for both cPanel and WHM
        my $hostname = Cpanel::Hostname::gethostname();
        return 1 if $test_email eq $ENV{REMOTE_USER} . '@' . $hostname;

        my ( $localpart, $domain ) = Cpanel::Validate::EmailRFC::get_name_and_domain($test_email);
        my $domainowner = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner($domain);
        if ( $> == 0 ) {

            require Whostmgr::ACLS;

            # In WHM, check reseller access
            Whostmgr::ACLS::init_acls();
            return 1 if ( Whostmgr::ACLS::hasroot() || $domainowner eq $ENV{REMOTE_USER} || Whostmgr::AcctInfo::Owner::checkowner( $ENV{REMOTE_USER}, $domainowner ) );
        }
        else {
            # In cpanel, only check account access
            return 1 if $domainowner eq $ENV{REMOTE_USER};
        }
    }
    return 0;
}

sub _get_exim_pid_and_filehandle {
    my ($address) = @_;

    my @eximcmd = ( _EXIM_BIN(), Cpanel::Exim::Options::fetch_exim_options(), '-bt', '-d', $address );

    pipe my $rfh, my $wfh;

    my $pid = Cpanel::Exec::forked(
        \@eximcmd,
        sub {
            close $rfh;

            # The output we need to parse is the child’s STDERR, not its STDOUT.
            open \*STDOUT, '>>',  '/dev/null' or warn "open(>> /dev/null): $!";
            open \*STDERR, '>&=', $wfh        or warn "dup2(): $!";
            close $wfh;
        },
    );

    close $wfh;

    return ( $pid, $rfh );
}

sub _parse_userforward_router {
    my $trace_fh = shift();

    my $aliasfile;

    my @destinations;

    my $LINE;

    while ( $LINE = readline $trace_fh ) {
        chomp $LINE;

        last if $LINE =~ m{\A>>>>>>};
        last if $LINE =~ m{\A------};

        if ( $LINE =~ m{bytes read from (.*)\z} ) {
            $aliasfile = $1;
        }
        elsif ( $LINE =~ m{\Auserforward\s+router\s+generated\s+(.*)\z} ) {
            push @destinations, $1;
        }
    }

    return (
        $LINE,
        map { { aliasfile => $aliasfile, router => 'userforward', result => $_ } } @destinations
    );
}

1;
