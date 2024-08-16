package Cpanel::Template::Plugin::WpToolkitPlugin;

use cPstrict;
use IPC::Run;
use Data::Dumper;

use base 'Template::Plugin';
sub load ( $class, $context ) {
    my $stash = $context->stash();
    @{$stash}{
        'execute_wpt_command',
      } = (
        sub {
            my @commandArgs = ('/usr/local/bin/wp-toolkit');
            my @args = @_;
            @commandArgs = (@commandArgs, @args);
            push(@commandArgs, '-format');
            push(@commandArgs, 'json');

            IPC::Run::run \@commandArgs, \undef, \my $stdout, \my $stderr;
            return eval { Cpanel::JSON::Load( $stdout ) };
        }
      );

    return $class->SUPER::load($context);
}

1;
