package Cpanel::Email::Filter::Trace;

# cpanel - Cpanel/Email/Filter/Trace.pm             Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use Cpanel                ();
use Cpanel::Autodie       ();
use Cpanel::Debug         ();
use Cpanel::Encoder::Tiny ();
use Cpanel::LoadModule    ();
use Cpanel::Locale::Lazy 'lh';

=encoding utf-8

=head1 NAME

Cpanel::Email::Filter::Trace - Support code for UAPI trace_filter

=head1 SYNOPSIS

    Do not call this module directly.  It is only called
    from Cpanel::API::Email when needed.

=head2 tracefilter

Do not call this module directly.

This is the work-horse for UAPI's trace_filter (not to be confused w/deprecated API1 call)

NOTE: There is an API1 call that calls this function and depends on it
to do authorization and error-checking.

=cut

sub tracefilter {
    my ( $tracefile, $msg ) = @_;

    my $feature = 'blockers';
    if ( !Cpanel::hasfeature($feature) ) {
        return ( 0, lh()->maketext( 'This feature requires the “[_1]” option and is not enabled on your account.', $feature ) );
    }

    if ( $Cpanel::CPDATA{'DEMO'} ) {
        return ( 0, lh()->maketext( 'This feature “[_1]” is disabled in demo mode.', $feature ) );
    }

    my $exists = Cpanel::Autodie::exists($tracefile);

    if ( !$exists || !-r _ ) {
        return ( 0, lh()->maketext('You do not own an email filter that matches the given parameters.') );
    }

    Cpanel::LoadModule::load_perl_module('Cpanel::SafeRun::Object');
    my $run = Cpanel::SafeRun::Object->new(
        program => '/usr/sbin/sendmail',
        args    => [ "-v", "-bF", $tracefile ],
        stdin   => $msg,
    );

    if ( $run->CHILD_ERROR() ) {
        Cpanel::Debug::log_warn( "Could not trace a filter for the user $Cpanel::user due to an error: " . join( q< >, map { $run->$_() // () } qw( autopsy stdout stderr ) ) );
        return ( 0, $run->autopsy() );
    }

    # Not using Cpanel::CPAN::IO::Callback here to allow for the same ordering of output from before the refactor of this function
    my @stdout_lines = map { "$_\n" } split( /\n/, $run->stdout() );
    my @stderr_lines = map { "$_\n" } split( /\n/, $run->stderr() );

    my $return_message;
    my $stderr_message = '';
    my @matched_conditions;

    for my $line (@stderr_lines) {
        if ( $line =~ /^Condition\s+is\s+true:\s+error_message/ ) {
            $return_message .= "<b><u>Message is an error message</b></u>\n";
            last;
        }
        elsif ( $line =~ /^Condition\s+is\s+true:/ ) {
            $line =~ s/^Condition\s+is\s+true:\s+//g;
            push @matched_conditions, $line;
            next;
        }
        elsif ( $line =~ /^Condition\s+is\s+false/ ) {
            next;
        }
        elsif ( $line =~ /^Sub-condition\s+is\s+false/ ) {
            next;
        }
        elsif ( $line =~ /^Sub-condition\s+is\s+true:/ ) {
            $line =~ s/^Sub-condition\s+is\s+true:\s+//g;
            push @matched_conditions, "\t" . $line;
            next;
        }
        $stderr_message .= Cpanel::Encoder::Tiny::safe_html_encode_str($line);
    }

    if (@matched_conditions) {
        $return_message .= "\n<b><u>The Filter has matched the following condition(s): \n</u><blockquote>" . join( '', map { Cpanel::Encoder::Tiny::safe_html_encode_str($_) } reverse @matched_conditions ) . "</blockquote></b>\n";
    }
    $return_message .= $stderr_message;

    for my $line (@stdout_lines) {
        my $bold = ( $line =~ /Normal delivery will occur/ || $line =~ /Filtering set up at least one significant/ || $line =~ /No other deliveries will occur/ ) ? 1 : 0;
        $return_message .= "<b>" if $bold;
        $return_message .= Cpanel::Encoder::Tiny::safe_html_encode_str($line);
        $return_message .= "</b>" if $bold;
    }

    return ( 1, $return_message );
}

1;
