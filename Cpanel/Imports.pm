package Cpanel::Imports;

# cpanel - Cpanel/Imports.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

$Cpanel::Imports::VERSION = '0.02';

sub import {
    my $caller = caller;
    no strict 'refs';    ## no critic(ProhibitNoStrict)

    # use named function so all consumers get the same thing
    *{ $caller . '::logger' } = \&__logger;
    *{ $caller . '::locale' } = \&__locale;

    return;
}

my ( $logger, $locale );

sub _reset_lazy_facade {    # usually for testing
    $logger = undef;
    $locale = undef;
    return;
}

sub __logger {
    require Cpanel::Logger if !$INC{'Cpanel/Logger.pm'};
    if ( !$logger ) {    # return $var ||= XYZ->new; works but, we keep it super vanilla to make it more likley to perlcc OK
        $logger = Cpanel::Logger->new;
    }
    return $logger;
}

sub __locale {
    require Cpanel::Locale if !$INC{'Cpanel/Locale.pm'};
    if ( !$locale ) {    # return $var ||= XYZ->new; works but, we keep it super vanilla to make it more likley to perlcc OK
        $locale = Cpanel::Locale->get_handle;
    }
    return $locale;
}

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::Imports - Import all things deemed worthy by consensus of superseding cPanel’s no-import policy.

=head1 VERSION

This document describes Cpanel::Imports version 0.02

=head1 SYNOPSIS

    use Cpanel::Imports;

    say locale->maketext('Hello World');

    logger->die('Goodbye Cruel World');

=head1 DESCRIPTION

These functions act more like keywords (without really being keywords). Akin to how Dancer et al do their functions.

By nature this should remain a short list and only be things that are very common, low level, and important and only changed after thorough discussion.

Since these are globally used functions (as opposed to internal functions) that act more like keywords (without really being keywords) we do not preface them with an underscore.

Since they are not internal: tools extracting symbols from a class should be aware of the functions listed under INTERFACE.

=head1 INTERFACE

Imports the following functions:

=head2 locale

A Lazy Façade to the L<Cpanel::Locale> object.

    locale->numf(42)

Rationale:

Almost all of our code is (or should be) localized. Having this Lazy Façade negates the need to '$locale ||= Cpanel::Locale->get_handle()' before we call a locale method. It also negates the need to invent and maintain ad-hoc solutions that do the same.

=head2 logger

A Lazy Façade returns the L<Cpanel::Logger> object.

    logger->info(…)

Rationale:

Most of our code uses Cpanel::Logger. Having this Lazy Façade negates the need to '$logger ||= Cpanel::Logger->new()' before we call a logger method. It also negates the need to invent and maintain ad-hoc solutions that do the same.

=head1 DIAGNOSTICS

Throws no warnings or errors of its own.

=head1 DEPENDENCIES

These modules are use()ed by Cpanel::Imports so there is no need to use() them in code that use()s Cpanel::Imports.

L<Cpanel::Logger>

L<Cpanel::Locale>

=head1 RATIONALE

=head2 What about the no-import policy?

In the pre-discussion we established why we have the import policy we do and concluded that certain exceptions were OK as long as they were isolated incidents and the rational was clear and accepted by the people effected.

=head2 Why have this in its own module instead of having have each module import its stuff?

=over 4

=item 1. It encapsulates/documents any deviations from policy in one spot.

This makes it easier to work with by not needing to remember what classes do what.

=over 4

=item * e.g. Just use the one module and you have the goods. Not sure what the “goods” are? perldoc the one module and you will :)

=item * This makes it clear that it is not something we should do normally.

=item * This helps us keep any similar deviations consistent with each other.

=back

=item 2. Regarding façade pattern specifically, classes do not typically implement these themselves.

=back

=head2 How do we get something added to this module?

Present your idea and its rationale for why it is worthy of being available as a pseudo keyword in all code to the development team for discussion.

If there is consensus and vetting of concerns is complete: create a case (referencing the dev thread in question), add it to this module (bump the version), its tests, and its POD, then submit the merge request and let the thread know.

=head2 Does this import-via-symbol-table compile OK?

Yes, we verified during the discussion it will work w/ 5.6 and 5.14!

=head2 Can I avoid the import and use a fully qualified version of these functions?

No, the entire point of this module is to bring in the keyword-like functions in order to write cleaner more consistent code.

For example, compare:

    thing->foo(…);

to:

    Cpanel::Imports::thing()->foo(…);

In the latter case it’d be better to either use the imported façade C<thing> or the original module that C<thing> does the magic for.

If it seems foreign to you why not give it a shot and see the benefits for yourself.

If you are worried about tools seeing them as non-internal functions that need testing/documenting/etc see the DESCRIPTION’s note about extracting symbols from a class.
