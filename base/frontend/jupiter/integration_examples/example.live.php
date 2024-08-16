<?php
/* This is an example of how to use LiveAPI with cPanel themes
 * cPanel theme has adopted a bootstrap CSS base, for information on CSS classes to use
 * please see: http://bootstrap.com and http://styleguide.cpanel.net
 *
 * As for method available to the $cpanel object in the example, cpanel.php contains
 * etensive inline documentation in the PHP Doc format.  Taking a look at it is highly advised.
 *
 * You can also look at the test.live.php file shipped along side this example.
 */

include("/usr/local/cpanel/php/cpanel.php");
$cpanel = new CPANEL();
print $cpanel->header( "Some Example Page" );
?>

<div class="container">
	<div class="row">
		Here's a list of environment variables!<br />
	</div>
	<div class="row">
		<table class="table">
			<thead>
				<tr>
					<td>
						Name
					</td>
					<td>
						Something
					</td>
				</tr>
			</thead>
			<tbody>
<?php
foreach ($_ENV as $k => $v) {
	echo "<tr><td>" . htmlentities($k) . "</td><td>" . htmlentities($v) . "</td></tr>";
}
?>
			</tbody>
		</table>
	</div>
	<div>
		<button type="button" class="btn btn-primary active">Do nothing!</button><br />
	</div>
</div>
<?php
print $cpanel->footer();
$cpanel->end();
?>
