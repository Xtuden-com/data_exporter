<?php
/**
 * @author Ilja Neumann <ineumann@owncloud.com>
 *
 * @copyright Copyright (c) 2018, ownCloud GmbH
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
namespace OCA\DataExporter\Importer\MetadataImporter;

use OCA\DataExporter\Model\UserMetadata\User\Preference;
use OCP\IConfig;

class PreferencesImporter {

	/** @var IConfig  */
	private $config;

	public function __construct(IConfig $config) {
		$this->config = $config;
	}

	/**
	 * @param string $userId
	 * @param Preference[] $preferences
	 * @throws \OCP\PreConditionNotMetException
	 */
	public function import(string $userId, array $preferences) {
		foreach ($preferences as $preference) {
			$this->config->setUserValue(
				$userId,
				$preference->getAppId(),
				$preference->getConfigKey(),
				$preference->getConfigValue()
			);
		}
	}
}
