package Cpanel::DNS::Unbound;

# cpanel - Cpanel/DNS/Unbound.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::DNS::Unbound - Wrapper logic around CPAN L<DNS::Unbound>

=head1 SYNOPSIS

    my $ub = Cpanel::DNS::Unbound->new();

    @results = $ub->recursive_query_or_die('cpanel.net', 'A');

    $ub->forget_cached_results();

=cut

#----------------------------------------------------------------------

use DNS::Unbound ();

use Cpanel::Config::LoadCpConf      ();
use Cpanel::Context                 ();
use Cpanel::DNS::Rcodes             ();
use Cpanel::DNS::Unbound::Singleton ();
use Cpanel::Exception               ();
use Cpanel::Finally                 ();
use Cpanel::TempFH                  ();

# Overridden in tests.
our $_QUERY_INACTIVITY_TIMEOUT = 30;

use constant {
    _EINTR => 4,

    _DEBUGLEVEL => 2,
};

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new( %OPTS )

Instantiates this class.

%OPTS are:

=over

=item * C<timeout> - The inactivity timeout, in seconds.
Defaults to an internally-defined default.

This was initially a simple per-query timeout, but some installations have
DNS query throttling in place that causes parallel queries to take much
longer than the queries themselves would individually.

=item * C<unbound> - A DNS::Unbound instance

If no instance is passed, one will be created and workarounds will be enabled.

Passing in a DNS::Unbound instance is useful if you want to enable specific
config or prevent workarounds from being used.

=back

=cut

sub new ( $class, %OPTS ) {

    local $@;
    my $tempfh = Cpanel::TempFH::create();

    my $self = bless { _diag_fh => $tempfh }, $class;

    $self->{'_dns_recursive_query_pool_size'} = Cpanel::Config::LoadCpConf::loadcpconf_not_copy()->{'dns_recursive_query_pool_size'} || 0;
    $self->{'timeout'}                        = $OPTS{'timeout'}                                                                     || $_QUERY_INACTIVITY_TIMEOUT;
    $self->{'_unbound'}                       = $OPTS{'unbound'}                                                                     || $self->_create_unbound();
    $self->{_domain_to_zone}                  = {};

    return $self;
}

#----------------------------------------------------------------------

=head2 $obj = I<OBJ>->forget_cached_results()

Clears I<OBJ>’s cached query results.

=cut

sub forget_cached_results ($self) {

    # In case we ever expose the ability to set a custom verbosity
    # (originally built into this module but found not to be needed):
    my $verbosity = $self->{'_unbound'}->get_option('verbosity');

    undef $self->{'_unbound'};
    Cpanel::DNS::Unbound::Singleton::clear();
    $self->{'_unbound'} = $self->_create_unbound();

    $self->{'_unbound'}->set_option( verbosity => $verbosity );

    %{ $self->{'_domain_to_zone'} } = ();

    return $self;
}

#----------------------------------------------------------------------

=head2 @results = I<OBJ>->domains_are_registered( @DOMAINS )

Returns a list of L<Cpanel::Data::Result> objects that indicate the status
of the inquiry into each @DOMAINS’s registration status: truthy, falsy, or
a failure. Failures will be either a L<DNS::Unbound::X>
or L<Cpanel::Exception> instance.

This must be called in list context B<unless> @DOMAINS has exactly one
member.

=cut

sub domains_are_registered ( $self, @domains ) {

    if ( !@domains ) {
        require Carp;
        Carp::croak('Need domains!');
    }

    Cpanel::Context::must_be_list() if @domains > 1;

    require Cpanel::Data::Result;
    require Cpanel::DNS::Client;

    my %query_name_result;

    my %domain_possible_registered = map {
        my @possible = Cpanel::DNS::Client::get_possible_registered($_);
        @query_name_result{@possible} = ();

        ( $_ => \@possible );
    } @domains;

    my @queries = map { [ $_ => 'NS' ] } keys %query_name_result;

    my $results = $self->recursive_queries( \@queries );

    # This works because keys() always iterates in the same order
    # for a given hash.
    @query_name_result{ keys %query_name_result } = @$results;

    my @return;

    for my $domain (@domains) {
        my $possible_ar = $domain_possible_registered{$domain};

        push @return, Cpanel::Data::Result::try(
            sub {
                for my $possible (@$possible_ar) {
                    my $result = $query_name_result{$possible};

                    _die_if_query_failed($result);

                    my $ub_result = $result->{'result'};
                    #
                    # An empty, nonfailure response likely means that the TLD’s
                    # name server is buggy or misconfigured. However likely that
                    # may be, it’s not under our purview.
                    #
                    # We used to treat no-data the same as nxdomain,
                    # however we learned that the .lk nameservers will
                    # return A entries for domains but no NS entries so
                    # this lead to false negatives
                    #
                    #
                    # (We could log about it, but since the server admin can’t
                    # fix it that would likely just generate noise and tickets.)
                    #
                    return 1 if !$ub_result->{'nxdomain'};
                }

                return 0;
            }
        );
    }

    # splice() returns a list, not an array.
    return splice @return;
}

#----------------------------------------------------------------------

=head2 $results_ar = I<OBJ>->get_caa_for_domains( \@DOMAINS )

Retrieves CAA result sets for @DOMAINS. The return is a reference to an
array of C<Cpanel::Data::Result> objects. Success payloads are
the query result as given by C<recursive_queries()>.

B<TODO:> Change (or duplicate) C<recursive_queries()> to implement this.

=cut

sub get_caa_for_domains ( $self, $domains_ar ) {
    my @queries = map { [ $_ => 'CAA' ] } @$domains_ar;

    my $results_ar = $self->recursive_queries( \@queries );

    require Cpanel::Data::Result;
    return [
        map {
            Cpanel::Data::Result::try( sub { _die_if_query_failed($_); $_ } )
        } @$results_ar
    ];
}

#----------------------------------------------------------------------

=head2 @nss = I<OBJ>->get_nameservers_for_domain( $DOMAIN )

B<TIP:> Look at L<Cpanel::Async::GetNameservers> for an async
replacement for this function.

Returns a plain list of $DOMAIN’s nameservers, or empty if that
list cannot be discerned.

Failures cause an empty return and warnings.

In scalar context this returns the number of
items that would have been returned in list context.

=cut

sub get_nameservers_for_domain ( $self, $domain ) {

    my $nameservers_by_domain_hr = $self->get_nameservers_for_domains($domain);

    my $nss_ar;

    if ( ref $nameservers_by_domain_hr->{$domain} ) {
        $nss_ar = $nameservers_by_domain_hr->{$domain};
    }

    return $nss_ar ? @$nss_ar : ();
}

#----------------------------------------------------------------------

=head2 @nss = I<OBJ>->get_nameservers_for_domains( @DOMAINS )

B<TIP:> Look at L<Cpanel::Async::GetNameservers> for an async
replacement for this function.

Like C<get_nameservers_for_domain()> but for multiple domains concurrently.
Returns a plain list of $DOMAIN’s nameservers, or empty if that
list cannot be discerned.

Failures prompt warnings.

=cut

sub get_nameservers_for_domains ( $self, @domains ) {

    require Cpanel::DNS::Client;
    my %maybe_registered_by_domain = map { $_ => [ Cpanel::DNS::Client::get_possible_registered($_) ] } @domains;
    my %queries;
    foreach my $domain (@domains) {
        my @maybe_registered_by_domain = @{ $maybe_registered_by_domain{$domain} };
        @queries{@maybe_registered_by_domain} = (undef) x scalar @maybe_registered_by_domain;
    }
    my @all_queries = sort keys %queries;
    my %name_to_query;
    my $ret = $self->_recursive_queries_with_warn( [ ( map { [ $_, 'NS' ] } @all_queries ) ] );
    foreach my $name (@all_queries) {
        $name_to_query{$name} = shift @$ret;
    }
    my %nameservers_by_domain;
  DOMAIN:
    foreach my $domain (@domains) {
        for my $maybe_registered ( @{ $maybe_registered_by_domain{$domain} } ) {
            my $response = $name_to_query{$maybe_registered} or next;
            $response->{'result'}                            or next;
            $response->{'decoded_data'}                      or next;
            my @nameservers = @{ $response->{'decoded_data'} } or next;
            $self->{_domain_to_zone}{$domain} = $maybe_registered;
            $nameservers_by_domain{$domain} = \@nameservers;
            next DOMAIN;
        }
    }
    return \%nameservers_by_domain;
}

#----------------------------------------------------------------------

=head2 $zone = I<OBJ>->get_zone_for_domain( $DOMAIN )

Determines the DNS zone that serves $DOMAIN’s records, or undef
if no such zone can be found.

Failures prompt warnings as in C<recursive_queries()>.

=cut

sub get_zone_for_domain ( $self, $domain ) {

    return $self->{_domain_to_zone}{$domain} if $self->{_domain_to_zone}{$domain};

    $self->get_nameservers_for_domain($domain);

    return $self->{_domain_to_zone}{$domain};
}

#----------------------------------------------------------------------

=head2 $domain_results_hr = I<OBJ>->get_records_by_domains( $TYPE, @DOMAINS )

Queries DNS for $TYPE records for each of @DOMAINS.

Returns a hash reference: ( $domain => \@values, … )

This warns on DNS errors.

=cut

sub get_records_by_domains ( $self, $qtype, @domains ) {

    my $ret = $self->_recursive_queries_with_warn( [ map { [ $_, $qtype ] } @domains ] );

    my %results_by_domain;
    foreach my $domain (@domains) {
        my $result = shift @$ret;

        if ($result) {
            my $ar = $result->{'decoded_data'};
            $ar ||= $result->{'result'}{'data'};

            $result = $ar;
        }

        $results_by_domain{$domain} = $result;
    }
    return \%results_by_domain;
}

=head2 @results = I<OBJ>->recursive_query_or_die( $NAME, $TYPE )

Returns the results of a DNS query, as a list. Throws an exception if
an error prevents the query from executing. See L<recursive_queries()>’s
C<error> return for what this can be.

In scalar context this returns the number of
items that would have been returned in list context.

(NB: This does B<not> throw an error if the query returns but indicates
an error.)

=cut

sub recursive_query_or_die ( $self, $name, $qtype ) {
    my $ret = $self->recursive_queries( [ [ $name, $qtype ] ] );

    $ret = $ret->[0];

    _die_if_query_failed($ret);

    my $data_ar = $ret->{'decoded_data'} || $ret->{'result'}{'data'};

    return @$data_ar;
}

sub _die_if_query_failed ($ret) {
    my ( $name, $qtype ) = @{$ret}{ 'name', 'qtype' };

    # Throw query errors (i.e., errors from DNS::Unbound).
    die if local $@ = $ret->{'error'};

    my ( $is_fatal, $err ) = analyze_dns_unbound_result_for_error( $name, $qtype, $ret->{'result'} );

    if ($err) {
        die $err if $is_fatal;
        warn $err;
    }

    return;
}

=head2 ($fatal, $err) = I<CLASS>->analyze_dns_unbound_result_for_error( $name, $qtype, $result )

Analyzes the result of an Unbound query for error conditions.

=over

=item Input

=over

=item $name

The name being queried

=item $qtype

The type of record being queried

=item $result

The Unbound result object for the query

=back

=item Output

This function returns nothing if there is no error, if an error is present it returns a list with two values:

=over

=item $fatal

Whether or not the DNS result encountered a fatal.

The only case where an error is generated but not considered fatal is if the Unbound result has query results and a non-zero rcode.

=item $err

An error message describing what went wrong.

=back

=back

=cut

sub analyze_dns_unbound_result_for_error {
    my ( $name, $qtype, $result ) = @_;

    if ( !$result->{'data'} || !@{ $result->{'data'} } ) {

        # We quietly ignore NXDOMAIN, but other failure-state
        # rcodes are an error.
        if ( !$result->{'nxdomain'} && $result->{'rcode'} > 0 ) {
            return ( 1, Cpanel::Exception::create( 'DNS::ErrorResponse', [ result => $result ] ) );
        }
    }

    # This seems like it’ll be pretty edge-case-y:
    elsif ( $result->{'rcode'} > 0 ) {
        my $code_txt = Cpanel::DNS::Rcodes::RCODE()->[ $result->{'rcode'} ];
        return ( 0, "DNS query ($name, $qtype) gave result but indicated error: $code_txt\n" );
    }

    return;
}

#----------------------------------------------------------------------

=head2 @results = I<OBJ>->recursive_query( $NAME, $TYPE )

Like C<recursive_query_or_die()> but logs to C<Cpanel::Debug::log_warn()>
rather than throwing an exception.

This function will return empty if the query receives a failure response or
times out.

=cut

sub recursive_query ( $self, $name, $qtype ) {
    my @r;

    local $@;
    eval { @r = $self->recursive_query_or_die( $name, $qtype ); 1 } or do {
        _warn_query_failure( $name, $qtype, $@ );
    };

    return @r;
}

sub _warn_query_failure ( $name, $qtype, $err ) {
    require Cpanel::Debug;
    Cpanel::Debug::log_warn("DNS query failure ($name/$qtype): $err");

    return;
}

#----------------------------------------------------------------------

=head2 $queries_ar = I<OBJ>->recursive_queries( \@QUERIES )

@QUERIES is a list of two-member arrays, each of which is: [ $name => $type ].

The return is a reference to an array of hash references; each hash
reference is:

=over

=item * C<name>

=item * C<qtype>

=item * C<error> - The error, if any, that prevented the DNS query from
returning: an instance of either L<Cpanel::Exception::Timeout> or
L<DNS::Unbound::X::ResolveError>.

=item * C<debug> - A string that gives the trace output from libunbound.

=item * C<result> - The returned hash reference from L<DNS::Unbound>’s
query resolution.

=item * C<decoded_data> - For recognized record types, a copy of the
C<result.data> array members, transformed thus:

=over

=item * C<A> and C<AAAA> records are given as ASCII.

=item * C<NS>, C<CNAME>, and C<PTR> records are given as domain names,
B<without> a trailing C<.>.

=item * C<MX> records are given as array references: [priority, name],
with the name’s trailing C<.> trimmed.

=item * C<TXT> records are given as a single string that plainly concatenates
the component character-strings together. This prevents applications from
distinguishing, e.g., (C<hello there>) from (C<hello>, C< there>), but it’s
the way cPanel & WHM has worked for some time.

=item * C<SOA> records return only the serial number.

=back

(Feel free to add decoders for other types as is useful.)

=back

B<NOTE:> This does B<NOT> warn nor throw an exception on DNS failures.
The responsibility to check for those is on you.

=cut

sub recursive_queries ( $self, $name_qtypes_ar ) {

    my $restore_debug_finally = $self->_log_to_tempfh();

    my $queries_ar = $self->_send_queries($name_qtypes_ar);

    $self->_poll_for_queries($queries_ar);
    $self->_xform_queries($queries_ar);

    return $queries_ar;
}

sub _poll_for_queries ( $self, $queries_ar ) {
    my $unbound_fd = $self->{'_unbound'}->fd();
    vec( my $rin, $unbound_fd, 1 ) = 1;

    while ( grep { !$_->{'done'} } @$queries_ar ) {
        my $got = select( my $rout = $rin, undef, undef, $self->{'timeout'} );

        if ( $got > 0 ) {
            if ( $self->{'_unbound'}->poll() ) {
                $self->{'_unbound'}->process();
            }
        }
        elsif ( $got == 0 ) {

            # We get here if we reached the inactivity timeout. We thus
            # time out all pending queries.
            $self->_cancel_and_mark_queries_as_timed_out($queries_ar);
        }
    }
    return;
}

sub _send_queries ( $self, $name_qtypes_ar ) {

    my @queries = map {
        {
            'name'   => $_->[0],
            'qtype'  => $_->[1],
            'result' => undef,
            'debug'  => undef,
            'error'  => undef,
            'object' => undef,
            'done'   => 0,
        }
    } @$name_qtypes_ar;

    return $self->_send_query_hrs( \@queries );
}

sub _send_query_hrs ( $self, $queries_ar ) {
    my $pool_size_setting = $self->{'_dns_recursive_query_pool_size'};

    # Setting the pool size to 0 disables the pooling.
    my $pool_size = ( 0 + $pool_size_setting ) || @$queries_ar;

    my $dns_ub = $self->{'_unbound'};

    my @left_to_enqueue = @$queries_ar;

    # Here we generate a pool of unbound async query promises
    # based on the dns_recursive_query_pool_size.  If the setting
    # is 0 we generate query promises for all queries right always
    # aka "a stampede" in some cases.
    #

    for ( 1 .. $pool_size ) {
        _create_next_query_promise( $dns_ub, \@left_to_enqueue ) or last;
    }

    return $queries_ar;
}

sub _create_next_query_promise ( $dns_ub, $queries_left_ar ) {
    my $query_hr = shift @$queries_left_ar or return;

    my ( $name, $qtype ) = @{$query_hr}{qw(name qtype)};

    $query_hr->{'object'} = $dns_ub->resolve_async( $name, $qtype )->then(
        sub {
            $query_hr->{'result'} = shift;
        },
        sub {
            $query_hr->{'error'} = shift;
        },
    )->then(
        sub {
            $query_hr->{'done'} = 1;

            # When each promise completes it generates another promise
            # if there are more queries to process left in
            # the bucket
            _create_next_query_promise( $dns_ub, $queries_left_ar );

            # Important that we _not_ return another query/promise here.
            return;
        }
    );

    return $query_hr;
}

sub _cancel_and_mark_queries_as_timed_out ( $self, $queries_ar ) {
    my $diag = $self->_collect_diag();

    my @pending_query_hrs;

    foreach my $query (@$queries_ar) {

        # Ignore queries that are finished.
        next if $query->{'done'};

        # We need to time out all pending queries--but ONLY those
        # that are pending. Any that haven’t gotten started yet
        # should be sent off (subject to throttling).

        if ( $query->{'object'} ) {
            $query->{'object'}->cancel();
            my ( $name, $qtype ) = @{$query}{qw(name qtype)};
            $query->{'error'} = Cpanel::Exception::create_raw( 'Timeout', "DNS query ($name/$qtype) timeout!", [ debug => $diag ] );
            $query->{'debug'} = $diag;
            $query->{'done'}  = 1;
        }
        else {
            # Since there is no object this means the query
            # was never sent due to the pool size limit
            # imposed by the  dns_recursive_query_pool_size
            # setting.  We need to enqueue it for send
            # in the next batch of queries since it never
            # got a chance to be sent before we hit the timeout.
            push @pending_query_hrs, $query;
        }
    }

    if (@pending_query_hrs) {

        # If there are still pending queries this means
        # that are some that have not yet been sent
        # because number of queries that can be running
        # at once as defined by dns_recursive_query_pool_size
        # which _send_query_hrs observes was reached.

        # Since we got here it means we can send the next
        # pool of queries. Since _send_query_hrs operates
        # on the hashrefs stored in @pending_query_hrs
        # it will take care of setting the 'done' flag
        # on the hashrefs that _poll_for_queries since
        # they are the same hashrefs in $queries_ar
        $self->_send_query_hrs( \@pending_query_hrs );
    }

    return;
}

sub _log_to_tempfh ($self) {
    my $diagfh  = $self->{'_diag_fh'};
    my $unbound = $self->{'_unbound'};

    my $old_verbosity = $self->{'_unbound'}->get_option('verbosity');

    # This module originally supported setting custom debug levels,
    # but that functionality ended up not being useful. We retain
    # the logic below in the event that we ever need to expose
    # that functionality again.
    $unbound->debuglevel( _DEBUGLEVEL() );

    $unbound->debugout( $self->{'_diag_fh'} );

    my $restore_logging_finally = Cpanel::Finally->new(
        sub {
            $unbound->debuglevel($old_verbosity);
            $unbound->debugout( \*STDERR );
        }
    );
    sysseek( $diagfh, 0, 0 ) // warn "seek() on diag fh: $!";
    truncate( $diagfh, 0 )   // warn "truncate() on diag fh: $!";
    return $restore_logging_finally;
}

sub _xform_queries ( $self, $queries_ar ) {

    my $diag = $self->_collect_diag();

    foreach my $query (@$queries_ar) {

        $query->{'debug'} = $diag;

        delete @{$query}{ 'object', 'done' };

        my ( $qtype, $result ) = @{$query}{qw(qtype result)};

        if ( !$result ) {
            next;
        }
        if ( my $xform_cr = __PACKAGE__->can("__xform_$qtype") ) {
            $query->{'decoded_data'} = [ @{ $result->{'data'} } ];

            $xform_cr->( $query->{'decoded_data'} );
        }
    }
    return;
}

# cheap inet_ntoa()
sub __xform_A {
    @{ $_[0] } = map { join '.', unpack( 'C4', $_ ) } @{ $_[0] };

    return;
}

# cheap inet_ntop()
sub __xform_AAAA {
    @{ $_[0] } = map { join ':', unpack( '(H4)*', $_ ) } @{ $_[0] };

    return;
}

sub __xform_MX {
    for my $rr ( @{ $_[0] } ) {
        $rr = [ unpack 'na*', $rr ];
        $rr->[1] = DNS::Unbound::decode_name( $rr->[1] );

        substr( $rr->[1], -1 ) eq '.' && chop $rr->[1];
    }

    return;
}

sub __xform_NS {
    $_ = DNS::Unbound::decode_name($_) for @{ $_[0] };

    substr( $_, -1 ) eq '.' && chop for @{ $_[0] };

    return;
}

*__xform_PTR = *__xform_CNAME = *__xform_NS;

sub __xform_TXT {
    $_ = DNS::Unbound::decode_character_strings($_) for @{ $_[0] };

    # TXT records are NOT strings, but *arrays* of strings.
    # (Each string is up to 255 bytes in length.)
    #
    # Alas, we have lots of code (APIs and UIs) that models TXT records
    # as strings, so we likely will need to retain this pattern for the
    # foreseeable future.
    $_ = join q<>, @$_ for @{ $_[0] };

    return;
}

sub __xform_SOA {

    # The existing behavior in Cpanel::DnsRoots::Resolver for SOA is to just return the serial
    #$_ = unpack( 'N', substr( $_, -20, 4 ) ) for @{ $_[0] };

    # The routine below would decode all of the SOA data if we ever wanted to do that
    # UPDATE: we do.
    my ($data) = @_;

    foreach my $rec (@$data) {

        my @numeric    = unpack( 'N5',     substr( $rec, -20 ) );
        my @name_comps = unpack( '(C/a)*', substr( $rec, 0, -20 ) );

        my @names;
        my $i = 0;
        for ( 0 .. $#name_comps ) {
            if ( length $name_comps[$_] ) {
                $names[$i] .= "$name_comps[$_].";
            }
            else {
                $i++;
            }
        }

        $rec = {};
        @{$rec}{qw(mname rname serial refresh retry expire minimum)} = ( @names, @numeric );
    }

    return;
}

sub __xform_CAA {
    local ( $@, $! );
    require Cpanel::DnsUtils::CAA;

    $_ = [ Cpanel::DnsUtils::CAA::decode_rdata($_) ] for @{ $_[0] };

    return;
}

sub _create_unbound ($self) {

    # DANGER -- DANGER -- DANGER
    #
    # Do not set ->debugout to the tempfh here as
    # creating a new unbound will close any previous tempfhs because
    # ub_ctx_create (called in DNS::Unbound->new()) closes the debugout
    #
    # Reported in: https://github.com/NLnetLabs/unbound/issues/52
    #
    # To work around this we do not set debugout
    # until the query and then unset it
    #

    return Cpanel::DNS::Unbound::Singleton::get();
}

sub _collect_diag ($self) {

    my $diagfh = $self->{'_diag_fh'};

    my $len = sysseek( $diagfh, 0, 1 ) // warn "seek(0, 1) on diag fh: $!";
    sysseek( $diagfh, 0, 0 ) // warn "seek(0, 0) on diag fh: $!";

    my $buf = '';
    local $!;

    while (1) {
        my $got = sysread( $diagfh, $buf, $len, length $buf );

        if ( !defined $got ) {
            next if $! == _EINTR();
            warn "read($len) on diag fh: $!";
        }

        last if !$got;
    }

    return $buf;
}

# Would it be worthwhile to expose this?
sub _recursive_queries_with_warn ( $self, $name_qtypes_ar ) {
    my $queries_ar = $self->recursive_queries($name_qtypes_ar);

    for my $q (@$queries_ar) {
        if ( my $err = $q->{'error'} ) {
            if ( $err->isa('Cpanel::Exception::Timeout') ) {
                _warn_query_failure( @{$q}{ 'name', 'qtype' }, "Timeout!" );
            }
            else {
                _warn_query_failure( @{$q}{ 'name', 'qtype', 'error' } );
            }
        }
        else {
            my ( undef, $err ) = analyze_dns_unbound_result_for_error( @{$q}{ 'name', 'qtype', 'result' } );
            _warn_query_failure( @{$q}{ 'name', 'qtype' }, $err->to_string() ) if $err;
        }
    }

    return $queries_ar;
}

sub DESTROY {
    delete $_[0]{'_unbound'};
    return;
}

1;
