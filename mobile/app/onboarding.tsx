import React from 'react';
import {
  Keyboard,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  SafeAreaView,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { useRouter } from 'expo-router';

import * as Haptics from 'expo-haptics';

import { useUserProfile } from '@/src/store/user-profile';
import type { Faith, Interest, Profession } from '@/src/store/user-profile';

const NAVY = '#0F1C3F';
const GOLD = '#D4A843';
const TOTAL_STEPS = 3;

const PROFESSIONS: { value: Profession; label: string; emoji: string }[] = [
  { value: 'architect', label: 'Architect', emoji: '🏛️' },
  { value: 'historian', label: 'Historian', emoji: '📜' },
  { value: 'photographer', label: 'Photographer', emoji: '📷' },
  { value: 'artist', label: 'Artist', emoji: '🎨' },
  { value: 'engineer', label: 'Engineer', emoji: '⚙️' },
  { value: 'doctor', label: 'Doctor', emoji: '🩺' },
  { value: 'foodie', label: 'Foodie', emoji: '🍽️' },
  { value: 'student', label: 'Student', emoji: '📚' },
  { value: 'writer', label: 'Writer', emoji: '✍️' },
  { value: 'other', label: 'Other', emoji: '✦' },
];

const INTERESTS: { value: Interest; label: string; emoji: string }[] = [
  { value: 'history', label: 'History', emoji: '⏳' },
  { value: 'architecture', label: 'Architecture', emoji: '🏛️' },
  { value: 'art', label: 'Art', emoji: '🖼️' },
  { value: 'religion', label: 'Religion', emoji: '🕌' },
  { value: 'food', label: 'Food & Drink', emoji: '🍜' },
  { value: 'nature', label: 'Nature', emoji: '🌿' },
  { value: 'nightlife', label: 'Nightlife', emoji: '🌙' },
  { value: 'music', label: 'Music', emoji: '🎵' },
  { value: 'photography', label: 'Photography', emoji: '📸' },
  { value: 'sports', label: 'Sports', emoji: '⚽' },
];

const FAITHS: { value: Faith; label: string }[] = [
  { value: 'muslim', label: 'Muslim' },
  { value: 'christian', label: 'Christian' },
  { value: 'jewish', label: 'Jewish' },
  { value: 'buddhist', label: 'Buddhist' },
  { value: 'hindu', label: 'Hindu' },
  { value: 'secular', label: 'Secular / Non-religious' },
  { value: 'prefer_not_to_say', label: 'Prefer not to say' },
];

export default function OnboardingScreen() {
  const router = useRouter();
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
            <Text style={styles.wordmark}>PIRI</Text>
            <Text style={styles.tagline}>The world through your eyes</Text>
            <Text style={styles.welcomeBody}>
              Answer a few questions and Piri will explain every place — every monument, mosque, ruin, restaurant — through the lens of who you are.
            </Text>
          </View>
          <Pressable style={styles.goldButton} onPress={() => { Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium); setStep(1); }}>
            <Text style={styles.goldButtonText}>Begin</Text>
          </Pressable>
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
          <Text style={styles.stepLabel}>{step} / {TOTAL_STEPS}</Text>
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
          <Pressable style={styles.skipButton} onPress={next}>
            <Text style={styles.skipText}>Skip</Text>
          </Pressable>
          <Pressable style={styles.continueButton} onPress={next}>
            <Text style={styles.continueText}>{step === TOTAL_STEPS ? 'Done' : 'Continue'}</Text>
          </Pressable>
        </View>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

function StepName({ name, onChange }: { name: string; onChange: (v: string) => void }) {
  return (
    <View style={styles.stepContainer}>
      <Text style={styles.stepTitle}>What should we call you?</Text>
      <Text style={styles.stepSubtitle}>Optional — used to personalize how Piri talks to you.</Text>
      <TextInput
        style={styles.textInput}
        placeholder="Your name"
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
  return (
    <View style={styles.stepContainer}>
      <Text style={styles.stepTitle}>What do you do?</Text>
      <Text style={styles.stepSubtitle}>
        Piri tailors its explanations to your expertise. An architect hears about structure; a historian about context.
      </Text>
      <View style={styles.chipGrid}>
        {PROFESSIONS.map(({ value, label, emoji }) => {
          const active = selected === value;
          return (
            <Pressable
              key={value}
              style={[styles.chip, active && styles.chipActive]}
              onPress={() => { Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light); onSelect(value); }}>
              <Text style={styles.chipEmoji}>{emoji}</Text>
              <Text style={[styles.chipText, active && styles.chipTextActive]}>{label}</Text>
            </Pressable>
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
  return (
    <View style={styles.stepContainer}>
      <Text style={styles.stepTitle}>A bit more about you</Text>
      <Text style={styles.stepSubtitle}>Both optional. Skip anything you'd rather not share.</Text>

      <Text style={styles.sectionLabel}>Interests</Text>
      <View style={styles.chipGrid}>
        {INTERESTS.map(({ value, label, emoji }) => {
          const active = selectedInterests.includes(value);
          return (
            <Pressable
              key={value}
              style={[styles.chip, active && styles.chipActive]}
              onPress={() => { Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light); onToggleInterest(value); }}>
              <Text style={styles.chipEmoji}>{emoji}</Text>
              <Text style={[styles.chipText, active && styles.chipTextActive]}>{label}</Text>
            </Pressable>
          );
        })}
      </View>

      <Text style={[styles.sectionLabel, { marginTop: 28 }]}>Faith & perspective</Text>
      <Text style={styles.faithNote}>
        Helps Piri frame sacred and historic spaces — a mosque explained to a Muslim differs from one explained to an architect.
      </Text>
      <View style={styles.chipGrid}>
        {FAITHS.map(({ value, label }) => {
          const active = selectedFaith === value;
          return (
            <Pressable
              key={value}
              style={[styles.chip, active && styles.chipActive]}
              onPress={() => { Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light); onSelectFaith(value); }}>
              <Text style={[styles.chipText, active && styles.chipTextActive]}>{label}</Text>
            </Pressable>
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
