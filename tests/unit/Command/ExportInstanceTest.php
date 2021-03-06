<?php
/**
 * @author Ilja Neumann <ineumann@owncloud.com>
 *
 * @copyright Copyright (c) 2019, ownCloud GmbH
 * @license GPL-2.0
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the Free
 * Software Foundation; either version 2 of the License, or (at your option)
 * any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
 * more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 */
namespace OCA\DataExporter\Tests\Unit\Command;

use OCA\DataExporter\Command\ExportInstance;
use OCA\DataExporter\InstanceExporter;
use PHPUnit\Framework\TestCase;
use Symfony\Component\Console\Tester\CommandTester;

class ExportInstanceTest extends TestCase {

	/** @var \PHPUnit_Framework_MockObject_MockObject|InstanceExporter */
	private $exporter;

	/** @var CommandTester */
	private $commandTester;

	public function setUp(): void {
		$this->exporter = $this->getMockBuilder(InstanceExporter::class)
			->disableOriginalConstructor()
			->getMock();

		$command = new ExportInstance($this->exporter);
		$this->commandTester = new CommandTester($command);
	}

	public function testInstanceImportReceivesCorrectArguments() {
		$this->exporter->expects($this->once())
			->method('export')
			->with($this->equalTo('/tmp'));

		$this->commandTester->execute([
			'exportDirectory' => '/tmp',
		]);
	}
}
