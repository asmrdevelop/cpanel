
# cpanel - Cpanel/cPAddons/Script/Runner/Cli.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::cPAddons::Script::Runner::Cli;

use strict;
use warnings;

use Cpanel::Imports;
use Cpanel::FindBin                     ();
use Cpanel::SafeRun::Object             ();
use Cpanel::cPAddons::Script::Arguments ();
use Cpanel::Encoder::Tiny               ();

=head1 NAME

Cpanel::cPAddons::Script::Runner::Cli

=head1 SYNOPSIS

Utility class to run a particular binary or script with a set of arguments derived from the passed script hash ref and data hash ref.

    package Session;

    use Cpanel::cPAddons::Notices ();

    sub new {
        my($pck)=@_;
        my $log = Cpanel::cPAddons::Notices::singleton();

        bless {
            notices => $log,
        }, $pck;
    }

    sub add_pre {
        return $_[0]->{notices}->add_pre($_[1], $_[2], $_[3])
    }

    sub add_error {
        return $_[0]->{notices}->add_error($_[1], $_[2], $_[3])
    }

    1;

    package Main;

    use Cpanel::cPAddons::Script::Runner::Cli ();

    package Session;

    use Cpanel::cPAddons::Notices ();

    sub new {
        my($pck)=@_;
        my $log = Cpanel::cPAddons::Notices::singleton();

        bless {
            notices => $log,
        }, $pck;
    }

    sub add_pre {
        return shift->{notices}->add_pre(@_)
    }

    sub add_error {
        return shift->{notices}->add_error(@_)
    }

    1;

    package Main;

    use Session ();
    use Cpanel::cPAddons::Script::Runner::Cli ();

    my $script_def = {
        description => "Running dir command",
        run         => "cli",
        name        => "ls",
        args        => [
            "-l",
            "[% data.dir_path %]"
        ]
    };

    my $session = Session->new();

    my $ok = Cpanel::cPAddons::Script::Runner::Cli::run(
        $script_def,
        $session,
        {
            data => {
                dir_path => "/home/tommy"
            }
        }
    );

    if ($ok) {
        my @messages = map { $_->{message} } @{$session->{notices}->get_list() || []};
        print "Script ran:\n" . join("\n", @messages) . "\n";
    }
    else {
        my @errors = map { $_->{message} } grep {
            $_->{type} eq "error" || $_->{type} eq "critical_error"
        } @{$session->{notices}->get_list() || []};
        print "Script failed: \n" . join("\n", @errors) . "\n";
    }

=head1 METHODS

=head2 Cpanel::cPAddons::Script::Runner::Cli::run()

Runs the passed in script definition object.

=head3 ARGUMENTS

=over 1

=item - script | hash ref | a configured script object with the following properties

=over 1

=item - script.description - optional string - reported in the session notices at start of run.

=item - script.run - string - type of run. Once of: cli or http or https. Must be cli for use with this module.

=item - script.name - string - path to the binary to run. May be either full path, relative path, or just the name of the binary if its in the users path. Note the users path may be very limited based on how this is called via Cpanel::SafeRun::Object.

=item - script.args - optional array ref - list of arguments and/or argument expansions.  See Cpanel::cPAddons::Script::Arguments for details of the expansion format.

=back

=item - session | hash ref | generally created with the Cpanel::cPAddons::Obj class. It must expose at least the add_pre, add_error, add_critical_error, add_warning, add_info, add_success, and add_html methods that proxy to a notices property containing an instances of Cpanel::cPAddons::Notices.

=item - data | hash ref | data used in script argument expansion.

=back

=head3 RETURNS

truthy value if the script run succeeded or falsey value if the script run failed.

=head3 SIDE EFFECTS

The method also adds notification entries to the notification collection on the session object.

=cut

sub run {
    my ( $script, $session, $data ) = @_;

    my $script_path = $script->{name};
    if ( !$script_path ) {
        $session->add_error(
            locale()->maketext(
                'The script does not contain the name property.',
            )
        );
        return;
    }

    if ( !-e $script_path ) {

        # Try to find it since it probably a command name or relative path
        $script_path = Cpanel::FindBin::findbin( $script->{name} );
    }
    elsif ( !-x _ && !-l $script_path ) {
        $session->add_error(
            locale()->maketext(
                'The “[_1]” script is not an executable.',
                Cpanel::Encoder::Tiny::safe_html_encode_str($script_path),
            )
        );
        return;
    }

    if ( !$script_path ) {
        $session->add_error(
            locale()->maketext(
                'The system could not locate the executable path: [_1]',
                Cpanel::Encoder::Tiny::safe_html_encode_str( $script->{name} ),
            )
        );
        return;
    }

    # Process parameters
    my $params;
    if ( $data->{environment}{debug} && $script->{debug_args} ) {
        $params = $script->{debug_args};
    }
    else {
        $params = $script->{args};
    }
    $params = Cpanel::cPAddons::Script::Arguments::expand_parameters( $params, $data )
      if $params && ref $params eq 'ARRAY' && @$params;

    # Process stdin
    my $stdin = '';
    if ( $script->{stdin} ) {
        $stdin = Cpanel::cPAddons::Script::Arguments::expand_parameter( $script->{stdin}, $data );
    }

    if ( $data->{environment}{verbose} ) {
        my @arg_list = @$params;
        if ($stdin) {
            my $stdin_clean = $stdin;
            $stdin_clean =~ s{\n}{, }g;
            push @arg_list, 'stdin=' . $stdin_clean;
        }

        $session->add_pre(
            locale()->maketext(
                'The system is running the install script from the cli: [_1]',
                Cpanel::Encoder::Tiny::safe_html_encode_str($script_path),
            ) . "\n" . locale()->maketext('Parameters:'),
            list_items => \@arg_list,
        );
    }

    $session->add_pre( $script->{description} )
      if $script->{description} && $data->{environment}{verbose};

    my %args = (
        program     => $script_path,
        args        => $params,
        before_exec => sub {
            $ENV{PATH} = '/usr/local/bin/:' . $ENV{PATH};
        },
    );
    $args{stdin} = $stdin if $stdin;

    my $run = Cpanel::SafeRun::Object->new(%args);

    if ( !$run ) {
        $session->add_error(
            locale()->maketext(
                'The system could not run the install script: [_1]',
                Cpanel::Encoder::Tiny::safe_html_encode_str($script_path)
            )
        );
        return;
    }
    elsif ( my $error_code = $run->error_code() ) {
        my $message = $run->stderr() || $run->stdout();
        chomp($message);
        $session->add_error(
            locale()->maketext(
                'The system could not run the “[_1]” install script and received the error code “[_2]”: [_3]',
                Cpanel::Encoder::Tiny::safe_html_encode_str($script_path),
                Cpanel::Encoder::Tiny::safe_html_encode_str($error_code),
                Cpanel::Encoder::Tiny::safe_html_encode_str($message),
            )
        );
        return;
    }
    else {
        my $out = $run->stdout();
        chomp($out);
        $session->add_pre($out) if $data->{environment}{verbose};
    }

    return 1;
}

1;
