<?php
/**
 * @author Ilja Neumann <ineumann@owncloud.com>
 * @author Juan Pablo Villafáñez <jvillafanez@solidgeargroup.com>
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
namespace OCA\DataExporter\Extractor;

use OCA\DataExporter\Extractor\MetadataExtractor\FilesMetadataExtractor;
use OCA\DataExporter\Extractor\MetadataExtractor\PreferencesExtractor;
use OCA\DataExporter\Extractor\MetadataExtractor\SharesExtractor;
use OCA\DataExporter\Extractor\MetadataExtractor\TrashBinExtractor;
use OCA\DataExporter\Extractor\MetadataExtractor\UserExtractor;
use OCA\DataExporter\Model\Metadata;
use OCP\Files\NotFoundException;
use OCP\IURLGenerator;
use Symfony\Component\OptionsResolver\OptionsResolver;

/**
 * Responsible for assembling all model objects which are required
 * for building metadata.json
 *
 * Each model object is read by its own specialized extractor
 *
 * @package OCA\DataExporter\Exporter
 */
class MetadataExtractor {

	/** @var UserExtractor  */
	private $userExtractor;
	/** @var PreferencesExtractor  */
	private $preferencesExtractor;
	/** @var FilesMetadataExtractor $filesMetadataExtractor */
	private $filesMetadataExtractor;
	/** @var SharesExtractor */
	private $sharesExtractor;
	/** @var TrashBinExtractor */
	private $trashBinExtractor;
	/** @var IURLGenerator */
	private $urlGenerator;
	/** @var OptionsResolver  */
	private $optionsResolver;

	/**
	 * @param UserExtractor $userExtractor
	 * @param PreferencesExtractor $preferencesExtractor
	 * @param FilesMetadataExtractor $filesMetadataExtractor
	 * @param SharesExtractor $sharesExtractor
	 * @param TrashBinExtractor $trashBinExtractor
	 * @param IURLGenerator $urlGenerator
	 */
	public function __construct(
		UserExtractor $userExtractor,
		PreferencesExtractor $preferencesExtractor,
		FilesMetadataExtractor $filesMetadataExtractor,
		SharesExtractor $sharesExtractor,
		TrashBinExtractor $trashBinExtractor,
		IURLGenerator $urlGenerator
	) {
		$this->userExtractor = $userExtractor;
		$this->preferencesExtractor = $preferencesExtractor;
		$this->filesMetadataExtractor = $filesMetadataExtractor;
		$this->trashBinExtractor = $trashBinExtractor;
		$this->sharesExtractor = $sharesExtractor;
		$this->urlGenerator = $urlGenerator;

		$optionsResolver = new OptionsResolver();
		$this->configureOptions($optionsResolver);
		$this->optionsResolver = $optionsResolver;
	}

	private function configureOptions(OptionsResolver $resolver) {
		$resolver->setRequired('trashBinAvailable');
		$resolver->setDefaults(['exportFileIds' => false]);
	}

	/**
	 * Extract all metadata required for export in to the database
	 *
	 * @param string $uid
	 * @return Metadata
	 * @throws \Exception
	 * @throws \RuntimeException if user can not be read
	 */
	public function extract($uid, $exportPath, $options = []) {
		$options = $this->optionsResolver->resolve($options);
		$user = $this->userExtractor->extract($uid);
		$user->setPreferences($this->preferencesExtractor->extract($uid));
		$metadata = new Metadata();
		$metadata->setDate(new \DateTimeImmutable())
			->setUser($user)
			->setOriginServer($this->urlGenerator->getAbsoluteURL('/'));

		$this->filesMetadataExtractor->extract($uid, $exportPath, $options['exportFileIds']);

		if ($options['trashBinAvailable']) {
			try {
				$this->trashBinExtractor->extract($uid, $exportPath);
			} catch (NotFoundException $ex) {
				//TODO: Log Folder not found in storage
			}
		}

		$this->sharesExtractor->extract($uid, $exportPath);

		return $metadata;
	}
}
