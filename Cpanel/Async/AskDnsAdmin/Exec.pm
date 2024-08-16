package Cpanel::Async::AskDnsAdmin::Exec;

# cpanel - Cpanel/Async/AskDnsAdmin/Exec.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Async::AskDnsAdmin::Exec

=head1 SYNOPSIS

    my $promise = Cpanel::Async::AskDnsAdmin::Exec::ask(
        '/path/to/dnsadmin/bin',
        'GETZONES',
        [ 'skipself' ],     #i.e., remote-only
        { zone => 'texas.com,california.com' },
    );

=head1 DESCRIPTION

This module implements client logic for async dnsadmin queries that
run a command rather than querying a dnsadmin daemon.

=cut

# perl -MCpanel::Async::AskDnsAdmin::Exec -MCpanel::PromiseUtils -MData::Dumper -e'print Dumper( Cpanel::PromiseUtils::wait_anyevent( Cpanel::Async::AskDnsAdmin::Exec::ask("/usr/local/cpanel/whostmgr/bin/dnsadmin", "GETZONES", [], { zone => "texas.com" }) )->get() )'

#----------------------------------------------------------------------

use AnyEvent         ();
use AnyEvent::Handle ();

use Promise::XS ();

use Cpanel::Async::Exec       ();
use Cpanel::Autodie           ();
use Cpanel::HTTP::QueryString ();
use Cpanel::LoadModule        ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 promise(?) = ask( $PATH, $QUESTION, \@CMD_ARGS, \%OPTS )

$PATH is the path to the dnsadmin command,
$QUESTION is the name (e.g., C<GETZONES>) of the query,
@CMD_ARGS are the command-line args to the command, and
%OPTS are the opts to give to the query itself.

The return matches that from the C<ask*> methods of
L<Cpanel::DnsUtils::AskDnsAdmin>. (In fact, those methods wrap this
function.)

=cut

sub ask ( $path, $question_str, $cmd_args_ar, $opts_hr ) {    ## no critic qw(ManyArgs) - mis-parse
    my $query_class = Cpanel::LoadModule::load_perl_module("Cpanel::DnsAdmin::Query::$question_str");

    my $payload = Cpanel::HTTP::QueryString::make_query_string($opts_hr);
    substr( $payload, 0, 0, "$question_str\n" );

    my ( $stdin_fh, $stdout_fh );

    my $execer = Cpanel::Async::Exec->new();

    my $process_obj = $execer->exec(
        program => $path,
        args    => $cmd_args_ar,
        stdin   => \$stdin_fh,
        stdout  => \$stdout_fh,
        stderr  => \*STDERR,
        timeout => 5,
    );

    my $stdin_ae = AnyEvent::Handle->new(
        fh       => $stdin_fh,
        on_error => sub ( $stdin_ae, $, $msg ) {
            warn "Output to $path: $msg";
            $stdin_ae->destroy();
        },
    );

    $stdin_ae->push_write($payload);
    $stdin_ae->on_drain( sub { close $stdin_fh } );

    my $stdout = q<>;

    my $read_deferred = Promise::XS::deferred();

    my $read_w;
    $read_w = AnyEvent->io(
        fh   => $stdout_fh,
        poll => 'r',
        cb   => sub {
            my ( $readsz, $buf );

            eval { $readsz = Cpanel::Autodie::sysread_sigguard( $stdout_fh, $buf, 65536 ); };

            if ($readsz) {
                $stdout .= $buf;
            }
            elsif ( defined $readsz ) {
                undef $read_w;
                $read_deferred->resolve($stdout);
            }
            else {
                $read_deferred->reject("read from $path: $@");
            }
        },
    );

    return $process_obj->child_error_p()->then(
        sub ($err) {
            return $read_deferred->promise()->then(
                sub ($stdout) {
                    if ($err) {
                        require Cpanel::ChildErrorStringifier;
                        my $strobj = Cpanel::ChildErrorStringifier->new( $err, $path );
                        die $strobj->to_exception();
                    }

                    return $query_class->parse_response($stdout);
                }
            );
        }
    );
}

1;
