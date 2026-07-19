import React from 'react';
import {
  Keyboard,
  KeyboardAvoidingView,
  Platform,
  SafeAreaView,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';

import * as Haptics from 'expo-haptics';

import { AnimatedPressable } from '@/components/animated-pressable';
import { FAITHS, INTERESTS, PROFESSIONS } from '@/src/constants/profile-options';
import { useUserProfile } from '@/src/store/user-profile';
import type { Faith, Interest, Profession } from '@/src/store/user-profile';

const NAVY = '#0F1C3F';
const GOLD = '#D4A843';
const TOTAL_STEPS = 3;

export default function OnboardingScreen() {
  const router = useRouter();
  const { t } = useTranslation();
  const { setProfile, completeOnboarding } = useUserProfile();

  const [step, setStep] = React.useState(0);
  const [name, setName] = React.useState('');
  const [profession, setProfession] = React.useState<Profession | null>(null);
  const [interests, setInterests] = React.useState<Interest[]>([]);
  const [faith, setFaith] = React.useState<Faith | null>(null);

  const finish = () => {
    setProfile({ name: name.trim(), profession, interests, faith });
    completeOnboarding();
    router.replace('/(tabs)');
  };

  const next = () => {
    Keyboard.dismiss();
    if (step < TOTAL_STEPS) setStep(step + 1);
    else finish();
  };

  const toggleInterest = (value: Interest) =>
    setInterests((prev) =>
      prev.includes(value) ? prev.filter((i) => i !== value) : [...prev, value]
    );

  if (step === 0) {
    return (
      <View style={styles.welcome}>
        <SafeAreaView style={styles.welcomeInner}>
          <View style={styles.welcomeContent}>
            <Text style={styles.compass}>◈</Text>
            <Text style={styles.wordmark}>{t('onboarding.wordmark')}</Text>
            <Text style={styles.tagline}>{t('onboarding.tagline')}</Text>
            <Text style={styles.welcomeBody}>{t('onboarding.welcomeBody')}</Text>
          </View>
          <AnimatedPressable style={styles.goldButton} onPress={() => { Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium); setStep(1); }}>
            <Text style={styles.goldButtonText}>{t('onboarding.begin')}</Text>
          </AnimatedPressable>
        </SafeAreaView>
      </View>
    );
  }

  return (
    <SafeAreaView style={styles.container}>
      <KeyboardAvoidingView
        style={{ flex: 1 }}
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}>
        {/* Progress */}
        <View style={styles.progressRow}>
          <View style={styles.progressTrack}>
            <View style={[styles.progressFill, { width: `${(step / TOTAL_STEPS) * 100}%` }]} />
          </View>
          <Text style={styles.stepLabel}>{t('onboarding.stepOf', { step, total: TOTAL_STEPS })}</Text>
        </View>

        <ScrollView
          contentContainerStyle={styles.scrollContent}
          keyboardShouldPersistTaps="handled"
          showsVerticalScrollIndicator={false}>

          {step === 1 && (
            <StepName name={name} onChange={setName} />
          )}
          {step === 2 && (
            <StepProfession selected={profession} onSelect={setProfession} />
          )}
          {step === 3 && (
            <StepFaithInterests
              selectedInterests={interests}
              onToggleInterest={toggleInterest}
              selectedFaith={faith}
              onSelectFaith={setFaith}
            />
          )}
        </ScrollView>

        <View style={styles.footer}>
          <AnimatedPressable style={styles.skipButton} onPress={next}>
            <Text style={styles.skipText}>{t('common.skip')}</Text>
          </AnimatedPressable>
          <AnimatedPressable style={styles.continueButton} onPress={next}>
            <Text style={styles.continueText}>{step === TOTAL_STEPS ? t('common.done') : t('common.continue')}</Text>
          </AnimatedPressable>
        </View>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

function StepName({ name, onChange }: { name: string; onChange: (v: string) => void }) {
  const { t } = useTranslation();
  return (
    <View style={styles.stepContainer}>
      <Text style={styles.stepTitle}>{t('onboarding.name.title')}</Text>
      <Text style={styles.stepSubtitle}>{t('onboarding.name.subtitle')}</Text>
      <TextInput
        style={styles.textInput}
        placeholder={t('onboarding.name.placeholder')}
        placeholderTextColor="#999"
        value={name}
        onChangeText={onChange}
        autoFocus
        returnKeyType="done"
        autoCapitalize="words"
      />
    </View>
  );
}

function StepProfession({
  selected,
  onSelect,
}: {
  selected: Profession | null;
  onSelect: (v: Profession) => void;
}) {
  const { t } = useTranslation();
  return (
    <View style={styles.stepContainer}>
      <Text style={styles.stepTitle}>{t('onboarding.profession.title')}</Text>
      <Text style={styles.stepSubtitle}>{t('onboarding.profession.subtitle')}</Text>
      <View style={styles.chipGrid}>
        {PROFESSIONS.map(({ value, labelKey, emoji }) => {
          const active = selected === value;
          return (
            <AnimatedPressable
              key={value}
              style={[styles.chip, active && styles.chipActive]}
              onPress={() => { Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light); onSelect(value); }}>
              <Text style={styles.chipEmoji}>{emoji}</Text>
              <Text style={[styles.chipText, active && styles.chipTextActive]}>{t(labelKey)}</Text>
            </AnimatedPressable>
          );
        })}
      </View>
    </View>
  );
}

function StepFaithInterests({
  selectedInterests,
  onToggleInterest,
  selectedFaith,
  onSelectFaith,
}: {
  selectedInterests: Interest[];
  onToggleInterest: (v: Interest) => void;
  selectedFaith: Faith | null;
  onSelectFaith: (v: Faith) => void;
}) {
  const { t } = useTranslation();
  return (
    <View style={styles.stepContainer}>
      <Text style={styles.stepTitle}>{t('onboarding.faithInterests.title')}</Text>
      <Text style={styles.stepSubtitle}>{t('onboarding.faithInterests.subtitle')}</Text>

      <Text style={styles.sectionLabel}>{t('onboarding.faithInterests.interestsLabel')}</Text>
      <View style={styles.chipGrid}>
        {INTERESTS.map(({ value, labelKey, emoji }) => {
          const active = selectedInterests.includes(value);
          return (
            <AnimatedPressable
              key={value}
              style={[styles.chip, active && styles.chipActive]}
              onPress={() => { Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light); onToggleInterest(value); }}>
              <Text style={styles.chipEmoji}>{emoji}</Text>
              <Text style={[styles.chipText, active && styles.chipTextActive]}>{t(labelKey)}</Text>
            </AnimatedPressable>
          );
        })}
      </View>

      <Text style={[styles.sectionLabel, { marginTop: 28 }]}>{t('onboarding.faithInterests.faithLabel')}</Text>
      <Text style={styles.faithNote}>{t('onboarding.faithInterests.faithNote')}</Text>
      <View style={styles.chipGrid}>
        {FAITHS.map(({ value, labelKey }) => {
          const active = selectedFaith === value;
          return (
            <AnimatedPressable
              key={value}
              style={[styles.chip, active && styles.chipActive]}
              onPress={() => { Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light); onSelectFaith(value); }}>
              <Text style={[styles.chipText, active && styles.chipTextActive]}>{t(labelKey)}</Text>
            </AnimatedPressable>
          );
        })}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  // Welcome
  welcome: {
    flex: 1,
    backgroundColor: NAVY,
  },
  welcomeInner: {
    flex: 1,
    paddingHorizontal: 32,
    paddingBottom: 40,
    justifyContent: 'space-between',
  },
  welcomeContent: {
    flex: 1,
    justifyContent: 'center',
  },
  compass: {
    fontSize: 48,
    color: GOLD,
    marginBottom: 20,
  },
  wordmark: {
    fontSize: 52,
    fontWeight: '800',
    color: '#FFFFFF',
    letterSpacing: 10,
    marginBottom: 16,
  },
  tagline: {
    fontSize: 22,
    fontWeight: '300',
    color: GOLD,
    marginBottom: 24,
    letterSpacing: 0.5,
  },
  welcomeBody: {
    fontSize: 16,
    color: 'rgba(255,255,255,0.7)',
    lineHeight: 26,
  },
  goldButton: {
    backgroundColor: GOLD,
    borderRadius: 16,
    paddingVertical: 18,
    alignItems: 'center',
  },
  goldButtonText: {
    color: NAVY,
    fontSize: 18,
    fontWeight: '700',
    letterSpacing: 0.5,
  },

  // Step screens
  container: {
    flex: 1,
    backgroundColor: '#FFFFFF',
  },
  progressRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 20,
    paddingTop: 16,
    paddingBottom: 8,
    gap: 12,
  },
  progressTrack: {
    flex: 1,
    height: 3,
    backgroundColor: '#E5E7EB',
    borderRadius: 2,
    overflow: 'hidden',
  },
  progressFill: {
    height: '100%',
    backgroundColor: NAVY,
    borderRadius: 2,
  },
  stepLabel: {
    fontSize: 13,
    color: '#9CA3AF',
    fontVariant: ['tabular-nums'],
  },
  scrollContent: {
    paddingBottom: 24,
  },
  stepContainer: {
    paddingHorizontal: 24,
    paddingTop: 32,
  },
  stepTitle: {
    fontSize: 28,
    fontWeight: '700',
    color: NAVY,
    marginBottom: 10,
    lineHeight: 34,
  },
  stepSubtitle: {
    fontSize: 15,
    color: '#6B7280',
    lineHeight: 22,
    marginBottom: 28,
  },
  sectionLabel: {
    fontSize: 13,
    fontWeight: '600',
    color: '#9CA3AF',
    textTransform: 'uppercase',
    letterSpacing: 1,
    marginBottom: 14,
  },
  faithNote: {
    fontSize: 14,
    color: '#9CA3AF',
    lineHeight: 20,
    marginBottom: 14,
    marginTop: -8,
  },
  textInput: {
    borderWidth: 1.5,
    borderColor: '#E5E7EB',
    borderRadius: 14,
    paddingHorizontal: 18,
    paddingVertical: 16,
    fontSize: 18,
    color: '#111827',
    backgroundColor: '#F9FAFB',
  },
  chipGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 10,
  },
  chip: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderRadius: 50,
    borderWidth: 1.5,
    borderColor: '#E5E7EB',
    backgroundColor: '#F9FAFB',
  },
  chipActive: {
    backgroundColor: NAVY,
    borderColor: NAVY,
  },
  chipEmoji: {
    fontSize: 16,
  },
  chipText: {
    fontSize: 14,
    color: '#374151',
    fontWeight: '500',
  },
  chipTextActive: {
    color: '#FFFFFF',
  },

  // Footer
  footer: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 24,
    paddingVertical: 16,
    gap: 12,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: '#F3F4F6',
    backgroundColor: '#FFFFFF',
  },
  skipButton: {
    paddingVertical: 16,
    paddingHorizontal: 8,
  },
  skipText: {
    fontSize: 16,
    color: '#9CA3AF',
    fontWeight: '500',
  },
  continueButton: {
    flex: 1,
    backgroundColor: NAVY,
    borderRadius: 14,
    paddingVertical: 16,
    alignItems: 'center',
  },
  continueText: {
    color: '#FFFFFF',
    fontSize: 17,
    fontWeight: '700',
  },
});
