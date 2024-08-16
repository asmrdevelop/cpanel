package Install::RegenerateTokens;

# cpanel - install/RegenerateTokens.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent qw( Cpanel::Task );

use Cpanel::Debug           ();
use Cpanel::SafeRun::Object ();

our $VERSION = '1.0';

our $_SCRIPT_TO_REGENERATE_TOKENS = '/usr/local/cpanel/scripts/regenerate_tokens';

=head1 NAME

Install::RegenerateTokens - upcp post-install task module for regenerating hyperscaler tokens

=head1 DESCRIPTION

This is a one time task to regenerate the hyperscaler tokens

Install::RegenerateTokens->new->perform();

=over

=item Type: Fresh Install

=item Frequency: once

=item EOL: never

=back

=head1 METHODS

=over

=item new()

Constructor for Install::RegenerateTokens objects.

=cut

exit __PACKAGE__->runtask() unless caller;

sub new {
    my $proto = shift;
    my $self  = $proto->SUPER::new;

    $self->set_internal_name('regenerate_hyperscaler_tokens');
    $self->add_dependencies(qw( post ));

    return $self;
}

=item perform()

Method to do the actual work of the Install::RegenerateTokens task.

=over

=item *

Runs the script to regenerate the tokens, if the script had never been run.

=back

=cut

sub perform {
    my $self = shift;

    $self->do_once(
        version => 'hyperscaler_tokens2',
        eol     => 'never',
        code    => \&_regenerate_hyperscaler_tokens,
    );

    return 1;
}

sub _regenerate_hyperscaler_tokens {
    if ( $ENV{CPANEL_BASE_INSTALL} ) {

        # Initial install: Don't run the script, but do set the do_once touch file. Maintainers will change the touch
        # file name if they want it to run on upcp for existing instances that had the touch file set on install.
        Cpanel::Debug::log_info("Initial install: Marking $_SCRIPT_TO_REGENERATE_TOKENS task to be skipped.");
        return;
    }

    Cpanel::Debug::log_info("Running $_SCRIPT_TO_REGENERATE_TOKENS");
    Cpanel::SafeRun::Object->new_or_die( 'program' => $_SCRIPT_TO_REGENERATE_TOKENS );
    Cpanel::Debug::log_info("Finished $_SCRIPT_TO_REGENERATE_TOKENS");

    return;
}

=back

=cut

1;
